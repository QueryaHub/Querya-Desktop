//! Driver-agnostic SQL object tree (schemas → folders → objects → columns).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::TableSchema;
use serde::{Deserialize, Serialize};

/// Catalog node kinds. Extra variants reserved for later driver epics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SqlObjectKind {
    Schema,
    /// Virtual group under a schema (Tables, Functions, Indexes, …).
    Folder,
    Table,
    View,
    MaterializedView,
    Column,
    Index,
    Trigger,
    Function,
    Procedure,
    Sequence,
    /// User-defined type (enum / composite / domain / range).
    #[serde(rename = "type")]
    Type,
}

/// Schema-level folder keys (Flutter `connections_panel_pg_tree` parity).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SchemaFolderKind {
    Tables,
    Views,
    MaterializedViews,
    Functions,
    Sequences,
    Indexes,
    Triggers,
    Types,
}

impl SchemaFolderKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Tables => "tables",
            Self::Views => "views",
            Self::MaterializedViews => "materialized_views",
            Self::Functions => "functions",
            Self::Sequences => "sequences",
            Self::Indexes => "indexes",
            Self::Triggers => "triggers",
            Self::Types => "types",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Tables => "Tables",
            Self::Views => "Views",
            Self::MaterializedViews => "Materialized views",
            Self::Functions => "Functions",
            Self::Sequences => "Sequences",
            Self::Indexes => "Indexes",
            Self::Triggers => "Triggers",
            Self::Types => "Types",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|folder| folder.as_str() == s)
    }

    pub const ALL: [Self; 8] = [
        Self::Tables,
        Self::Views,
        Self::MaterializedViews,
        Self::Functions,
        Self::Sequences,
        Self::Indexes,
        Self::Triggers,
        Self::Types,
    ];
}

impl SqlObjectKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Schema => "schema",
            Self::Folder => "folder",
            Self::Table => "table",
            Self::View => "view",
            Self::MaterializedView => "materialized_view",
            Self::Column => "column",
            Self::Index => "index",
            Self::Trigger => "trigger",
            Self::Function => "function",
            Self::Procedure => "procedure",
            Self::Sequence => "sequence",
            Self::Type => "type",
        }
    }

    fn parse(s: &str) -> Option<Self> {
        match s {
            "schema" => Some(Self::Schema),
            "folder" => Some(Self::Folder),
            "table" => Some(Self::Table),
            "view" => Some(Self::View),
            "materialized_view" => Some(Self::MaterializedView),
            "column" => Some(Self::Column),
            "index" => Some(Self::Index),
            "trigger" => Some(Self::Trigger),
            "function" => Some(Self::Function),
            "procedure" => Some(Self::Procedure),
            "sequence" => Some(Self::Sequence),
            "type" => Some(Self::Type),
            _ => None,
        }
    }

    pub fn is_expandable(self) -> bool {
        matches!(
            self,
            Self::Schema
                | Self::Folder
                | Self::Table
                | Self::View
                | Self::MaterializedView
        )
    }

    pub fn is_relation(self) -> bool {
        matches!(
            self,
            Self::Table | Self::View | Self::MaterializedView
        )
    }
}

/// Stable tree node shared across IPC and UI.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct SqlObjectNode {
    /// Durable id, e.g. `sqlite:table:main:users`.
    pub id: String,
    pub name: String,
    pub kind: SqlObjectKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<String>,
    pub expandable: bool,
}

impl SqlObjectNode {
    pub fn new(
        id: String,
        name: String,
        kind: SqlObjectKind,
        schema: Option<String>,
        parent_id: Option<String>,
    ) -> Self {
        Self {
            id,
            name,
            kind,
            schema,
            parent_id,
            expandable: kind.is_expandable(),
        }
    }
}

/// Per-connection object tree. Drivers implement; registry returns Arc.
pub trait ObjectTreeProvider: Send + Sync {
    fn list_children(&self, parent_id: Option<&str>) -> ConnectionResult<Vec<SqlObjectNode>>;
    fn describe(&self, object_id: &str) -> ConnectionResult<TableSchema>;
}

/// Encode a path segment so `:` / `%` in names do not break ids.
pub fn enc_segment(s: &str) -> String {
    s.replace('%', "%25").replace(':', "%3A")
}

pub fn dec_segment(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = &s[i + 1..i + 3];
            if let Ok(v) = u8::from_str_radix(hex, 16) {
                out.push(v as char);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

pub fn schema_id(driver: DriverKind, schema: &str) -> String {
    format!("{}:schema:{}", driver.as_str(), enc_segment(schema))
}

pub fn folder_id(driver: DriverKind, schema: &str, folder: SchemaFolderKind) -> String {
    format!(
        "{}:folder:{}:{}",
        driver.as_str(),
        enc_segment(schema),
        folder.as_str()
    )
}

pub fn relation_id(driver: DriverKind, kind: SqlObjectKind, schema: &str, name: &str) -> String {
    debug_assert!(kind.is_relation());
    format!(
        "{}:{}:{}:{}",
        driver.as_str(),
        kind.as_str(),
        enc_segment(schema),
        enc_segment(name)
    )
}

pub fn column_id(driver: DriverKind, schema: &str, table: &str, column: &str) -> String {
    format!(
        "{}:column:{}:{}:{}",
        driver.as_str(),
        enc_segment(schema),
        enc_segment(table),
        enc_segment(column)
    )
}

/// Schema-scoped object (function / sequence / type / …).
pub fn named_object_id(
    driver: DriverKind,
    kind: SqlObjectKind,
    schema: &str,
    name: &str,
) -> String {
    format!(
        "{}:{}:{}:{}",
        driver.as_str(),
        kind.as_str(),
        enc_segment(schema),
        enc_segment(name)
    )
}

/// Index or trigger scoped to a relation: `driver:kind:schema:table:name`.
pub fn relation_child_id(
    driver: DriverKind,
    kind: SqlObjectKind,
    schema: &str,
    table: &str,
    name: &str,
) -> String {
    format!(
        "{}:{}:{}:{}:{}",
        driver.as_str(),
        kind.as_str(),
        enc_segment(schema),
        enc_segment(table),
        enc_segment(name)
    )
}

/// Parsed object id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedObjectId {
    Schema {
        driver: DriverKind,
        schema: String,
    },
    Folder {
        driver: DriverKind,
        schema: String,
        folder: SchemaFolderKind,
    },
    Relation {
        driver: DriverKind,
        kind: SqlObjectKind,
        schema: String,
        name: String,
    },
    Column {
        driver: DriverKind,
        schema: String,
        table: String,
        column: String,
    },
    /// Function / sequence / type / procedure under a schema.
    Named {
        driver: DriverKind,
        kind: SqlObjectKind,
        schema: String,
        name: String,
    },
    /// Index / trigger under a relation.
    RelationChild {
        driver: DriverKind,
        kind: SqlObjectKind,
        schema: String,
        table: String,
        name: String,
    },
}

fn bad_id(msg: impl Into<String>) -> ConnectionError {
    ConnectionError::invalid_config(msg)
}

fn parse_driver(s: &str) -> ConnectionResult<DriverKind> {
    match s {
        "sqlite" => Ok(DriverKind::Sqlite),
        "postgres" => Ok(DriverKind::Postgres),
        "mysql" => Ok(DriverKind::Mysql),
        other => Err(bad_id(format!("unknown driver in object id: {other}"))),
    }
}

pub fn parse_object_id(id: &str) -> ConnectionResult<ParsedObjectId> {
    let parts: Vec<&str> = id.split(':').collect();
    if parts.len() < 3 {
        return Err(bad_id(format!("invalid object id: {id}")));
    }
    let driver = parse_driver(parts[0])?;
    let kind = SqlObjectKind::parse(parts[1])
        .ok_or_else(|| bad_id(format!("unknown object kind in id: {id}")))?;

    match kind {
        SqlObjectKind::Schema if parts.len() == 3 => Ok(ParsedObjectId::Schema {
            driver,
            schema: dec_segment(parts[2]),
        }),
        SqlObjectKind::Folder if parts.len() == 4 => {
            let folder = SchemaFolderKind::parse(parts[3])
                .ok_or_else(|| bad_id(format!("unknown folder kind in id: {id}")))?;
            Ok(ParsedObjectId::Folder {
                driver,
                schema: dec_segment(parts[2]),
                folder,
            })
        }
        SqlObjectKind::Table | SqlObjectKind::View | SqlObjectKind::MaterializedView
            if parts.len() == 4 =>
        {
            Ok(ParsedObjectId::Relation {
                driver,
                kind,
                schema: dec_segment(parts[2]),
                name: dec_segment(parts[3]),
            })
        }
        SqlObjectKind::Column if parts.len() == 5 => Ok(ParsedObjectId::Column {
            driver,
            schema: dec_segment(parts[2]),
            table: dec_segment(parts[3]),
            column: dec_segment(parts[4]),
        }),
        SqlObjectKind::Function
        | SqlObjectKind::Procedure
        | SqlObjectKind::Sequence
        | SqlObjectKind::Type
            if parts.len() == 4 =>
        {
            Ok(ParsedObjectId::Named {
                driver,
                kind,
                schema: dec_segment(parts[2]),
                name: dec_segment(parts[3]),
            })
        }
        SqlObjectKind::Index | SqlObjectKind::Trigger if parts.len() == 5 => {
            Ok(ParsedObjectId::RelationChild {
                driver,
                kind,
                schema: dec_segment(parts[2]),
                table: dec_segment(parts[3]),
                name: dec_segment(parts[4]),
            })
        }
        _ => Err(bad_id(format!("invalid object id: {id}"))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_ids_with_colon_in_name() {
        let id = relation_id(DriverKind::Sqlite, SqlObjectKind::Table, "main", "a:b");
        assert_eq!(id, "sqlite:table:main:a%3Ab");
        match parse_object_id(&id).unwrap() {
            ParsedObjectId::Relation { name, schema, .. } => {
                assert_eq!(schema, "main");
                assert_eq!(name, "a:b");
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn column_id_round_trip() {
        let id = column_id(DriverKind::Sqlite, "main", "users", "id");
        assert_eq!(id, "sqlite:column:main:users:id");
        match parse_object_id(&id).unwrap() {
            ParsedObjectId::Column {
                schema,
                table,
                column,
                ..
            } => {
                assert_eq!(schema, "main");
                assert_eq!(table, "users");
                assert_eq!(column, "id");
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn folder_and_function_ids_round_trip() {
        let fid = folder_id(DriverKind::Postgres, "shop", SchemaFolderKind::Functions);
        assert_eq!(fid, "postgres:folder:shop:functions");
        match parse_object_id(&fid).unwrap() {
            ParsedObjectId::Folder { folder, schema, .. } => {
                assert_eq!(schema, "shop");
                assert_eq!(folder, SchemaFolderKind::Functions);
            }
            other => panic!("unexpected {other:?}"),
        }

        let fn_id = named_object_id(
            DriverKind::Postgres,
            SqlObjectKind::Function,
            "shop",
            "total_orders",
        );
        match parse_object_id(&fn_id).unwrap() {
            ParsedObjectId::Named { kind, name, .. } => {
                assert_eq!(kind, SqlObjectKind::Function);
                assert_eq!(name, "total_orders");
            }
            other => panic!("unexpected {other:?}"),
        }
    }
}
