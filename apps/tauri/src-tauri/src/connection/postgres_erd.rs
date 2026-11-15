//! PostgreSQL ER catalog — mirrors Flutter `ErdCatalog` pg_catalog queries.

use super::erd::{ErdColumn, ErdRelation, ErdSchema, ErdTable};
use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::runtime;
use sqlx::postgres::PgRow;
use sqlx::{PgPool, Row};
use std::collections::HashSet;

/// Load tables of `schema` (default: `current_schema()`) plus FKs.
///
/// When `focus` is set, only the neighbourhood within `depth` FK hops is kept.
/// Focus may be `table` or `schema.table`.
pub fn load_schema(
    pool: &PgPool,
    schema: Option<&str>,
    focus: Option<&str>,
    depth: usize,
) -> ConnectionResult<ErdSchema> {
    let schema_name = schema.map(str::to_owned);
    let relations = load_foreign_keys(pool)?;
    let mut tables = load_tables(pool, schema_name.as_deref())?;

    // Neighbourhood may pull tables from other schemas via qualified names.
    if let Some(focus) = focus {
        let all_rels = relations.clone();
        let names = super::erd::neighbourhood(&all_rels, focus, depth);
        let mut names = names;
        names.insert(focus.to_owned());
        // Also try bare name if focus was qualified and unused.
        if let Some((_, bare)) = focus.split_once('.') {
            if !all_rels.iter().any(|r| r.from_table == focus || r.to_table == focus)
                && all_rels
                    .iter()
                    .any(|r| r.from_table == bare || r.to_table == bare)
            {
                names = super::erd::neighbourhood(&all_rels, bare, depth);
                names.insert(bare.to_owned());
            }
        }
        // Fetch missing tables that live outside the requested schema.
        let have: HashSet<String> = tables.iter().map(|t| t.name.clone()).collect();
        for name in &names {
            if have.contains(name) {
                continue;
            }
            if let Some(extra) = load_one_table(pool, name)? {
                tables.push(extra);
            }
        }
        let mut schema = ErdSchema {
            tables,
            relations,
            truncated: false,
        };
        schema.mark_foreign_keys();
        schema.annotate_relations();
        schema.filter_tables(&names);
        return Ok(schema);
    }

    let filtered = filter_relations_to_tables(&relations, &tables);
    let mut schema = ErdSchema {
        tables,
        relations: filtered,
        truncated: false,
    };
    schema.mark_foreign_keys();
    schema.annotate_relations();
    Ok(schema)
}

fn filter_relations_to_tables(
    relations: &[ErdRelation],
    tables: &[ErdTable],
) -> Vec<ErdRelation> {
    let names: HashSet<&str> = tables.iter().map(|t| t.name.as_str()).collect();
    relations
        .iter()
        .filter(|r| names.contains(r.from_table.as_str()) && names.contains(r.to_table.as_str()))
        .cloned()
        .collect()
}

fn load_tables(pool: &PgPool, schema: Option<&str>) -> ConnectionResult<Vec<ErdTable>> {
    runtime::block_on(async {
        let rows = if let Some(schema) = schema {
            sqlx::query(
                "SELECT CASE WHEN ns.nspname = current_schema() THEN c.relname
                        ELSE ns.nspname || '.' || c.relname END AS table_name,
                        c.relname AS bare_name,
                        ns.nspname AS schema_name,
                        c.relkind::text AS relkind
                 FROM pg_catalog.pg_class c
                 JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
                 WHERE ns.nspname = $1
                   AND c.relkind IN ('r', 'p', 'v', 'm')
                 ORDER BY c.relkind, table_name",
            )
            .bind(schema)
            .fetch_all(pool)
            .await
        } else {
            sqlx::query(
                "SELECT CASE WHEN ns.nspname = current_schema() THEN c.relname
                        ELSE ns.nspname || '.' || c.relname END AS table_name,
                        c.relname AS bare_name,
                        ns.nspname AS schema_name,
                        c.relkind::text AS relkind
                 FROM pg_catalog.pg_class c
                 JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
                 WHERE ns.nspname = current_schema()
                   AND c.relkind IN ('r', 'p', 'v', 'm')
                 ORDER BY c.relkind, table_name",
            )
            .fetch_all(pool)
            .await
        }
        .map_err(pg_err)?;

        let mut tables = Vec::with_capacity(rows.len());
        for r in rows {
            let table_name: String = r.get("table_name");
            let bare: String = r.get("bare_name");
            let schema_name: String = r.get("schema_name");
            let relkind: String = r.get("relkind");
            let is_view = relkind == "v" || relkind == "m";
            let columns = load_columns(pool, &schema_name, &bare, is_view).await?;
            tables.push(ErdTable {
                name: table_name,
                schema: Some(schema_name),
                columns,
                is_view,
            });
        }
        Ok(tables)
    })
}

fn load_one_table(pool: &PgPool, qualified_or_bare: &str) -> ConnectionResult<Option<ErdTable>> {
    let (schema, bare) = match qualified_or_bare.split_once('.') {
        Some((s, t)) => (s.to_owned(), t.to_owned()),
        None => {
            // Resolve against current_schema.
            let current: String = runtime::block_on(async {
                sqlx::query_scalar("SELECT current_schema()")
                    .fetch_one(pool)
                    .await
                    .map_err(pg_err)
            })?;
            (current, qualified_or_bare.to_owned())
        }
    };

    runtime::block_on(async {
        let row = sqlx::query(
            "SELECT CASE WHEN ns.nspname = current_schema() THEN c.relname
                    ELSE ns.nspname || '.' || c.relname END AS table_name,
                    c.relkind::text AS relkind
             FROM pg_catalog.pg_class c
             JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
             WHERE ns.nspname = $1 AND c.relname = $2
               AND c.relkind IN ('r', 'p', 'v', 'm')
             LIMIT 1",
        )
        .bind(&schema)
        .bind(&bare)
        .fetch_optional(pool)
        .await
        .map_err(pg_err)?;

        let Some(r) = row else {
            return Ok(None);
        };
        let table_name: String = r.get("table_name");
        let relkind: String = r.get("relkind");
        let is_view = relkind == "v" || relkind == "m";
        let columns = load_columns(pool, &schema, &bare, is_view).await?;
        Ok(Some(ErdTable {
            name: table_name,
            schema: Some(schema),
            columns,
            is_view,
        }))
    })
}

async fn load_columns(
    pool: &PgPool,
    schema: &str,
    table: &str,
    is_view: bool,
) -> ConnectionResult<Vec<ErdColumn>> {
    let rows = sqlx::query(
        "SELECT a.attname AS column_name,
                format_type(a.atttypid, a.atttypmod) AS data_type,
                CASE WHEN pk.oid IS NULL THEN 0 ELSE 1 END AS is_pk,
                CASE WHEN a.attnotnull THEN 0 ELSE 1 END AS is_nullable,
                CASE WHEN EXISTS (
                  SELECT 1 FROM pg_catalog.pg_index ui
                  WHERE ui.indrelid = c.oid AND ui.indisunique AND NOT ui.indisprimary
                    AND ui.indnatts = 1 AND ui.indkey[0] = a.attnum
                    AND ui.indpred IS NULL
                ) THEN 1 ELSE 0 END AS is_unique,
                pg_get_expr(df.adbin, df.adrelid) AS column_default,
                CASE WHEN a.attidentity <> ''
                  OR pg_get_expr(df.adbin, df.adrelid) LIKE 'nextval(%'
                  THEN 1 ELSE 0 END AS is_identity
         FROM pg_catalog.pg_attribute a
         JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
         JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
         LEFT JOIN pg_catalog.pg_constraint pk
           ON pk.conrelid = c.oid AND pk.contype = 'p' AND a.attnum = ANY (pk.conkey)
         LEFT JOIN pg_catalog.pg_attrdef df
           ON df.adrelid = c.oid AND df.adnum = a.attnum
         WHERE ns.nspname = $1
           AND c.relname = $2
           AND a.attnum > 0 AND NOT a.attisdropped
         ORDER BY a.attnum",
    )
    .bind(schema)
    .bind(table)
    .fetch_all(pool)
    .await
    .map_err(pg_err)?;

    Ok(rows
        .into_iter()
        .map(|r: PgRow| {
            let is_pk = !is_view && r.get::<i32, _>("is_pk") == 1;
            ErdColumn {
                name: r.get("column_name"),
                data_type: r.get("data_type"),
                is_primary_key: is_pk,
                is_foreign_key: false,
                is_nullable: is_view || r.get::<i32, _>("is_nullable") == 1,
                is_unique: r.get::<i32, _>("is_unique") == 1,
                default_value: r.get("column_default"),
                is_identity: !is_view && r.get::<i32, _>("is_identity") == 1,
            }
        })
        .collect())
}

fn load_foreign_keys(pool: &PgPool) -> ConnectionResult<Vec<ErdRelation>> {
    runtime::block_on(async {
        let rows = sqlx::query(
            "SELECT CASE WHEN ns.nspname = current_schema() THEN src.relname
                    ELSE ns.nspname || '.' || src.relname END AS table_name,
                    sa.attname AS column_name,
                    CASE WHEN rn.nspname = current_schema() THEN ref.relname
                    ELSE rn.nspname || '.' || ref.relname END AS ref_table,
                    ra.attname AS ref_column
             FROM pg_catalog.pg_constraint con
             JOIN pg_catalog.pg_class src ON src.oid = con.conrelid
             JOIN pg_catalog.pg_namespace ns ON ns.oid = src.relnamespace
             JOIN pg_catalog.pg_class ref ON ref.oid = con.confrelid
             JOIN pg_catalog.pg_namespace rn ON rn.oid = ref.relnamespace
             CROSS JOIN LATERAL unnest(con.conkey, con.confkey) AS k(src_attnum, ref_attnum)
             JOIN pg_catalog.pg_attribute sa
               ON sa.attrelid = con.conrelid AND sa.attnum = k.src_attnum
             JOIN pg_catalog.pg_attribute ra
               ON ra.attrelid = con.confrelid AND ra.attnum = k.ref_attnum
             WHERE con.contype = 'f'
               AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
               AND ns.nspname NOT LIKE 'pg_toast%'
               AND rn.nspname NOT IN ('pg_catalog', 'information_schema')",
        )
        .fetch_all(pool)
        .await
        .map_err(pg_err)?;

        Ok(rows
            .into_iter()
            .map(|r| ErdRelation {
                from_table: r.get("table_name"),
                from_column: r.get("column_name"),
                to_table: r.get("ref_table"),
                to_column: r.get("ref_column"),
                optional: false,
                one_to_one: false,
            })
            .collect())
    })
}

fn pg_err(e: impl ToString) -> ConnectionError {
    ConnectionError::driver(DriverKind::Postgres, e.to_string())
}
