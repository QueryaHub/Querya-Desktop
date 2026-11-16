import type {
  SduiButtonVariant,
  SduiNode,
  SduiPanelNode,
  SduiStackDirection,
  SduiTextRole,
} from "./types";

const BUTTON_VARIANTS = new Set<SduiButtonVariant>([
  "primary",
  "secondary",
  "ghost",
  "destructive",
]);
const TEXT_ROLES = new Set<SduiTextRole>(["heading", "body", "muted"]);
const STACK_DIRS = new Set<SduiStackDirection>(["column", "row"]);
const GAPS = new Set(["sm", "md", "lg"]);

export class SduiParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SduiParseError";
  }
}

function asRecord(value: unknown, path: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new SduiParseError(`${path}: expected object`);
  }
  return value as Record<string, unknown>;
}

function parseChildren(raw: unknown, path: string): SduiNode[] {
  if (!Array.isArray(raw)) {
    throw new SduiParseError(`${path}: expected array`);
  }
  return raw.map((item, i) => parseSduiNode(item, `${path}[${i}]`));
}

/** Parse one SDUI node; throws [SduiParseError] on invalid input. */
export function parseSduiNode(raw: unknown, path = "$"): SduiNode {
  const obj = asRecord(raw, path);
  const type = obj.type;
  if (typeof type !== "string") {
    throw new SduiParseError(`${path}.type: required string`);
  }

  switch (type) {
    case "panel": {
      const title = obj.title;
      const id = obj.id;
      return {
        type: "panel",
        id: typeof id === "string" ? id : undefined,
        title: typeof title === "string" ? title : undefined,
        children: parseChildren(obj.children ?? [], `${path}.children`),
      };
    }
    case "text": {
      if (typeof obj.text !== "string") {
        throw new SduiParseError(`${path}.text: required string`);
      }
      const role = obj.role;
      return {
        type: "text",
        text: obj.text,
        role:
          typeof role === "string" && TEXT_ROLES.has(role as SduiTextRole)
            ? (role as SduiTextRole)
            : "body",
      };
    }
    case "button": {
      if (typeof obj.id !== "string" || !obj.id) {
        throw new SduiParseError(`${path}.id: required non-empty string`);
      }
      if (typeof obj.label !== "string") {
        throw new SduiParseError(`${path}.label: required string`);
      }
      const variant = obj.variant;
      const action = obj.action;
      return {
        type: "button",
        id: obj.id,
        label: obj.label,
        variant:
          typeof variant === "string" &&
          BUTTON_VARIANTS.has(variant as SduiButtonVariant)
            ? (variant as SduiButtonVariant)
            : "secondary",
        action: typeof action === "string" ? action : undefined,
      };
    }
    case "divider":
      return { type: "divider" };
    case "stack": {
      const direction = obj.direction;
      const gap = obj.gap;
      return {
        type: "stack",
        direction:
          typeof direction === "string" &&
          STACK_DIRS.has(direction as SduiStackDirection)
            ? (direction as SduiStackDirection)
            : "column",
        gap:
          typeof gap === "string" && GAPS.has(gap)
            ? (gap as "sm" | "md" | "lg")
            : "md",
        children: parseChildren(obj.children ?? [], `${path}.children`),
      };
    }
    default:
      throw new SduiParseError(`${path}.type: unknown "${type}"`);
  }
}

/** Root must be a `panel` node (host mounts one panel surface). */
export function parseSduiPanel(raw: unknown): SduiPanelNode {
  const node = parseSduiNode(raw, "$");
  if (node.type !== "panel") {
    throw new SduiParseError(`$: root must be type "panel", got "${node.type}"`);
  }
  return node;
}
