import { invoke } from "@tauri-apps/api/core";
import type { ConnectionProfile } from "./connection";

export type MongoFindResult = {
  documents: unknown[];
  truncated: boolean;
};

export async function dbConnectMongo(opts: {
  host: string;
  port: number;
  database: string;
  username?: string | null;
  password?: string | null;
  authSource?: string | null;
  id?: string | null;
}): Promise<string> {
  return invoke<string>("db_connect_mongo", {
    host: opts.host,
    port: opts.port,
    database: opts.database,
    username: opts.username ?? null,
    password: opts.password ?? null,
    authSource: opts.authSource ?? null,
    id: opts.id ?? null,
  });
}

export async function profilesConnectMongo(opts: {
  name: string;
  host: string;
  port: number;
  database: string;
  username?: string | null;
  password?: string | null;
  authSource?: string | null;
  folderId?: string | null;
  id?: string | null;
}): Promise<ConnectionProfile> {
  return invoke<ConnectionProfile>("profiles_connect_mongo", {
    request: {
      name: opts.name,
      host: opts.host,
      port: opts.port,
      database: opts.database,
      username: opts.username ?? null,
      password: opts.password ?? null,
      authSource: opts.authSource ?? null,
      folderId: opts.folderId ?? null,
      id: opts.id ?? null,
    },
  });
}

export async function mongoPing(id: string): Promise<string> {
  return invoke<string>("mongo_ping", { id });
}

export async function mongoListDatabases(id: string): Promise<string[]> {
  return invoke<string[]>("mongo_list_databases", { id });
}

export async function mongoListCollections(
  id: string,
  database: string,
): Promise<string[]> {
  return invoke<string[]>("mongo_list_collections", { id, database });
}

export async function mongoFind(
  id: string,
  opts: {
    database: string;
    collection: string;
    filterJson?: string | null;
    limit?: number | null;
  },
): Promise<MongoFindResult> {
  return invoke<MongoFindResult>("mongo_find", {
    id,
    database: opts.database,
    collection: opts.collection,
    filterJson: opts.filterJson ?? null,
    limit: opts.limit ?? null,
  });
}
