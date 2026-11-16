/** Host-driven SDUI panel descriptors (extension → Querya Vue). */

export type SduiButtonVariant = "primary" | "secondary" | "ghost" | "destructive";

export type SduiTextRole = "heading" | "body" | "muted";

export type SduiStackDirection = "column" | "row";

export type SduiTextNode = {
  type: "text";
  text: string;
  role?: SduiTextRole;
};

export type SduiButtonNode = {
  type: "button";
  id: string;
  label: string;
  variant?: SduiButtonVariant;
  /** Opaque action id the host/extension understands (e.g. `dismiss`). */
  action?: string;
};

export type SduiDividerNode = {
  type: "divider";
};

export type SduiStackNode = {
  type: "stack";
  direction?: SduiStackDirection;
  gap?: "sm" | "md" | "lg";
  children: SduiNode[];
};

export type SduiPanelNode = {
  type: "panel";
  id?: string;
  title?: string;
  children: SduiNode[];
};

export type SduiNode =
  | SduiPanelNode
  | SduiTextNode
  | SduiStackNode
  | SduiButtonNode
  | SduiDividerNode;

export type SduiActionEvent = {
  nodeId: string;
  action: string;
};
