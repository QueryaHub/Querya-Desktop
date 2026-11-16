import type { SduiPanelNode } from "./types";

/** Canonical sample descriptor for #1904 / hello-panel (#1905). */
export const SAMPLE_HELLO_PANEL_DESCRIPTOR: SduiPanelNode = {
  type: "panel",
  id: "querya.hello-panel",
  title: "Hello panel",
  children: [
    {
      type: "text",
      role: "heading",
      text: "Hello from SDUI",
    },
    {
      type: "text",
      role: "body",
      text: "This panel is rendered by the Querya Vue host from a JSON descriptor.",
    },
    {
      type: "text",
      role: "muted",
      text: "Extensions will mount panels like this over NDJSON RPC.",
    },
    { type: "divider" },
    {
      type: "stack",
      direction: "row",
      gap: "sm",
      children: [
        {
          type: "button",
          id: "hello.dismiss",
          label: "Dismiss",
          variant: "primary",
          action: "dismiss",
        },
        {
          type: "button",
          id: "hello.ping",
          label: "Ping host",
          variant: "secondary",
          action: "ping",
        },
      ],
    },
  ],
};
