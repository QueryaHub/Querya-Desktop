//! Driver-agnostic SQL object tree (schemas → tables/views → columns).

use super::error::{ConnectionError, ConnectionResult};
use super::id::DriverKind;
use super::introspect::TableSchema;
use serde::{Deserialize, Serialize};

/// Catalog node kinds. Extra variants reserved for later driver epics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SqlObjectKind {
    Schema,
    Table,
    View,
    Column,
    Index,
    Trigger,
    Function,
    Procedure,
}

impl SqlObjectKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Schema => "schema",
            Self::Table => "table",
            Self::View => "view",
            Self::Column => "column",
            Self::Index => "index",
            Self::Trigger => "trigger",
            Self::Function => "function",
            Self::Procedure => "procedure",
        }
    }

    fn parse(s: &str) -> Option<Self> {
        match s {
            "schema" => Some(Self::Schema),
            "table" => Some(Self::Table),
            "view" => Some(Self::View),
            "column" => Some(Self::Column),
            "index" => Some(Self::Index),
            "trigger" => Some(Self::Trigger),
            "function" => Some(Self::Function),
            "procedure" => Some(Self::Procedure),
            _ => None,
        }
    }

    pub fn is_expandable(self) -> bool {
        matches!(
            self,
            Self::Schema | Self::Table | Self::View | Self::Index | Self::Function | Self::Procedure
        )
    }

    pub fn is_relation(self) -> bool {
        matches!(self, Self::Table | Self::View)
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

/// Parsed object id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedObjectId {
    Schema {
        driver: DriverKind,
        schema: String,
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
}

fn bad_id(msg: impl Into<String>) -> ConnectionError {
    ConnectionError::invalid_config(msg)
}

pub fn parse_object_id(id: &str) -> ConnectionResult<ParsedObjectId> {
    let parts: Vec<&str> = id.split(':').collect();
    if parts.len() < 3 {
        return Err(bad_id(format!("invalid object id: {id}")));
    }
    let driver = match parts[0] {
        "sqlite" => DriverKind::Sqlite,
        "postgres" => DriverKind::Postgres,
        "mysql" => DriverKind::Mysql,
        other => return Err(bad_id(format!("unknown driver in object id: {other}"))),
    };
    let kind = SqlObjectKind::parse(parts[1])
        .ok_or_else(|| bad_id(format!("unknown object kind in id: {id}")))?;

    match kind {
        SqlObjectKind::Schema if parts.len() == 3 => Ok(ParsedObjectId::Schema {
            driver,
            schema: dec_segment(parts[2]),
        }),
        SqlObjectKind::Table | SqlObjectKind::View if parts.len() == 4 => {
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
        SqlObjectKind::Schema => Err(bad_id(format!("invalid schema id: {id}"))),
        SqlObjectKind::Table | SqlObjectKind::View => {
            Err(bad_id(format!("invalid relation id: {id}")))
        }
        SqlObjectKind::Column => Err(bad_id(format!("invalid column id: {id}"))),
        other => Err(bad_id(format!(
            "object kind {:?} not supported in ids yet",
            other
        ))),
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
}
