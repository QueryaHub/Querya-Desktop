import { invoke } from "@tauri-apps/api/core";
import type { ConnectionProfile } from "./connection";

export type RedisScanPage = {
  nextCursor: number;
  keys: string[];
};

export type RedisKeyMeta = {
  key: string;
  keyType: string;
  ttl: number;
};

export type RedisHashField = {
  field: string;
  value: string;
};

export type RedisZsetMember = {
  member: string;
  score: number;
};

export type RedisKeyView = {
  key: string;
  keyType: string;
  ttl: number;
  stringValue: string | null;
  hashFields: RedisHashField[];
  listValues: string[];
  setMembers: string[];
  zsetMembers: RedisZsetMember[];
};

export async function dbConnectRedis(opts: {
  host: string;
  port: number;
  password?: string | null;
  username?: string | null;
  db?: number | null;
  id?: string | null;
}): Promise<string> {
  return invoke<string>("db_connect_redis", {
    host: opts.host,
    port: opts.port,
    password: opts.password ?? null,
    username: opts.username ?? null,
    db: opts.db ?? null,
    id: opts.id ?? null,
  });
}

export async function profilesConnectRedis(opts: {
  name: string;
  host: string;
  port: number;
  database?: string | null;
  username?: string | null;
  password?: string | null;
  folderId?: string | null;
  id?: string | null;
}): Promise<ConnectionProfile> {
  return invoke<ConnectionProfile>("profiles_connect_redis", {
    request: {
      name: opts.name,
      host: opts.host,
      port: opts.port,
      database: opts.database ?? null,
      username: opts.username ?? null,
      password: opts.password ?? null,
      folderId: opts.folderId ?? null,
      id: opts.id ?? null,
    },
  });
}

export async function redisPing(id: string): Promise<string> {
  return invoke<string>("redis_ping", { id });
}

export async function redisScan(
  id: string,
  opts?: { cursor?: number; pattern?: string | null; count?: number },
): Promise<RedisScanPage> {
  return invoke<RedisScanPage>("redis_scan", {
    id,
    cursor: opts?.cursor ?? 0,
    pattern: opts?.pattern ?? null,
    count: opts?.count ?? 100,
  });
}

export async function redisGet(
  id: string,
  key: string,
): Promise<string | null> {
  return invoke<string | null>("redis_get", { id, key });
}

export async function redisSet(
  id: string,
  key: string,
  value: string,
): Promise<void> {
  await invoke("redis_set", { id, key, value });
}

export async function redisKeyMetas(
  id: string,
  keys: string[],
): Promise<RedisKeyMeta[]> {
  return invoke<RedisKeyMeta[]>("redis_key_metas", { id, keys });
}

export async function redisReadKey(
  id: string,
  key: string,
): Promise<RedisKeyView> {
  return invoke<RedisKeyView>("redis_read_key", { id, key });
}
