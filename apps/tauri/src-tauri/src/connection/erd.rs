//! ER diagram catalog DTOs — mirrors Flutter `ErdSchema` / `ErdTable` / `ErdRelation`.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// Column on an ER table card.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ErdColumn {
    pub name: String,
    pub data_type: String,
    pub is_primary_key: bool,
    pub is_foreign_key: bool,
    pub is_nullable: bool,
    #[serde(default)]
    pub is_unique: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_value: Option<String>,
    #[serde(default)]
    pub is_identity: bool,
}

/// Table (or view) node on the diagram.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ErdTable {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    pub columns: Vec<ErdColumn>,
    #[serde(default)]
    pub is_view: bool,
}

/// Foreign key edge: `from_table.from_column` → `to_table.to_column`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ErdRelation {
    pub from_table: String,
    pub from_column: String,
    pub to_table: String,
    pub to_column: String,
    /// Referencing column may be NULL.
    #[serde(default)]
    pub optional: bool,
    /// Referencing side is unique (1:1).
    #[serde(default)]
    pub one_to_one: bool,
}

/// Full (or neighbourhood) schema for the ER canvas.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ErdSchema {
    pub tables: Vec<ErdTable>,
    pub relations: Vec<ErdRelation>,
    #[serde(default)]
    pub truncated: bool,
}

impl ErdSchema {
    pub fn empty() -> Self {
        Self {
            tables: Vec::new(),
            relations: Vec::new(),
            truncated: false,
        }
    }

    /// Mark FK flags on columns that appear as relation sources.
    pub fn mark_foreign_keys(&mut self) {
        let mut fk_cols: HashSet<(String, String)> = HashSet::new();
        for r in &self.relations {
            fk_cols.insert((r.from_table.clone(), r.from_column.clone()));
        }
        for t in &mut self.tables {
            for c in &mut t.columns {
                if fk_cols.contains(&(t.name.clone(), c.name.clone())) {
                    c.is_foreign_key = true;
                }
            }
        }
    }

    /// Fill `optional` / `one_to_one` from column nullability / uniqueness / PK.
    pub fn annotate_relations(&mut self) {
        let mut by_name: HashMap<&str, &ErdTable> = HashMap::new();
        for t in &self.tables {
            by_name.insert(t.name.as_str(), t);
        }
        for r in &mut self.relations {
            let Some(src) = by_name.get(r.from_table.as_str()) else {
                continue;
            };
            let Some(col) = src.columns.iter().find(|c| c.name == r.from_column) else {
                continue;
            };
            r.optional = col.is_nullable;
            r.one_to_one = col.is_unique
                || (col.is_primary_key
                    && src
                        .columns
                        .iter()
                        .filter(|c| c.is_primary_key)
                        .count()
                        == 1);
        }
    }

    /// Keep only tables in `names` and relations whose both ends remain.
    pub fn filter_tables(&mut self, names: &HashSet<String>) {
        self.tables.retain(|t| names.contains(&t.name));
        self.relations
            .retain(|r| names.contains(&r.from_table) && names.contains(&r.to_table));
    }
}

/// Undirected BFS around `focus` over FK edges (Flutter `ErdCatalog.neighbourhood`).
pub fn neighbourhood(relations: &[ErdRelation], focus: &str, depth: usize) -> HashSet<String> {
    let mut adjacent: HashMap<&str, HashSet<&str>> = HashMap::new();
    for r in relations {
        adjacent
            .entry(r.from_table.as_str())
            .or_default()
            .insert(r.to_table.as_str());
        adjacent
            .entry(r.to_table.as_str())
            .or_default()
            .insert(r.from_table.as_str());
    }
    let mut seen: HashSet<String> = HashSet::from([focus.to_owned()]);
    let mut frontier: HashSet<String> = HashSet::from([focus.to_owned()]);
    for _ in 0..depth {
        if frontier.is_empty() {
            break;
        }
        let mut next = HashSet::new();
        for t in &frontier {
            if let Some(ns) = adjacent.get(t.as_str()) {
                for n in ns {
                    if seen.insert((*n).to_owned()) {
                        next.insert((*n).to_owned());
                    }
                }
            }
        }
        frontier = next;
    }
    seen
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neighbourhood_depth_one() {
        let rels = vec![
            ErdRelation {
                from_table: "orders".into(),
                from_column: "user_id".into(),
                to_table: "users".into(),
                to_column: "id".into(),
                optional: false,
                one_to_one: false,
            },
            ErdRelation {
                from_table: "order_items".into(),
                from_column: "order_id".into(),
                to_table: "orders".into(),
                to_column: "id".into(),
                optional: false,
                one_to_one: false,
            },
        ];
        let n = neighbourhood(&rels, "orders", 1);
        assert!(n.contains("orders"));
        assert!(n.contains("users"));
        assert!(n.contains("order_items"));
        assert_eq!(n.len(), 3);
    }

    #[test]
    fn mark_fk_and_annotate() {
        let mut schema = ErdSchema {
            tables: vec![ErdTable {
                name: "orders".into(),
                schema: None,
                is_view: false,
                columns: vec![
                    ErdColumn {
                        name: "id".into(),
                        data_type: "INTEGER".into(),
                        is_primary_key: true,
                        is_foreign_key: false,
                        is_nullable: false,
                        is_unique: false,
                        default_value: None,
                        is_identity: true,
                    },
                    ErdColumn {
                        name: "user_id".into(),
                        data_type: "INTEGER".into(),
                        is_primary_key: false,
                        is_foreign_key: false,
                        is_nullable: true,
                        is_unique: false,
                        default_value: None,
                        is_identity: false,
                    },
                ],
            }],
            relations: vec![ErdRelation {
                from_table: "orders".into(),
                from_column: "user_id".into(),
                to_table: "users".into(),
                to_column: "id".into(),
                optional: false,
                one_to_one: false,
            }],
            truncated: false,
        };
        schema.mark_foreign_keys();
        schema.annotate_relations();
        assert!(schema.tables[0].columns[1].is_foreign_key);
        assert!(schema.relations[0].optional);
        assert!(!schema.relations[0].one_to_one);
    }
}
