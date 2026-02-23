#!/usr/bin/env node
/**
 * Canopy MCP Server
 *
 * Model Context Protocol server for AI-native Canopy development.
 * Provides tools for building, type checking, and navigating Canopy projects.
 *
 * @module @canopy/mcp-server
 * @since 0.19.2
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListResourcesRequestSchema,
  ListToolsRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "child_process";
import { readFile, readdir, stat } from "fs/promises";
import { join, relative } from "path";

// Tool definitions for Canopy operations
const TOOLS = [
  {
    name: "canopy_build",
    description:
      "Build a Canopy project. Compiles all source files and generates JavaScript output.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description: "Path to the Canopy project directory (default: current directory)",
        },
        optimize: {
          type: "boolean",
          description: "Enable production optimizations (default: false)",
        },
        output: {
          type: "string",
          description: "Output file path (default: auto-detect)",
        },
        format: {
          type: "string",
          enum: ["iife", "esm", "commonjs"],
          description: "JavaScript output format (default: iife)",
        },
      },
    },
  },
  {
    name: "canopy_check",
    description:
      "Type check a Canopy project without generating output. Fast way to validate code.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description: "Path to the Canopy project directory (default: current directory)",
        },
      },
    },
  },
  {
    name: "canopy_get_type",
    description:
      "Get the type of an expression or function at a specific location in a Canopy file.",
    inputSchema: {
      type: "object" as const,
      properties: {
        file: {
          type: "string",
          description: "Path to the Canopy source file",
        },
        line: {
          type: "number",
          description: "Line number (1-indexed)",
        },
        column: {
          type: "number",
          description: "Column number (1-indexed)",
        },
      },
      required: ["file", "line", "column"],
    },
  },
  {
    name: "canopy_find_definition",
    description: "Find the definition location of a symbol in a Canopy file.",
    inputSchema: {
      type: "object" as const,
      properties: {
        file: {
          type: "string",
          description: "Path to the Canopy source file",
        },
        line: {
          type: "number",
          description: "Line number (1-indexed)",
        },
        column: {
          type: "number",
          description: "Column number (1-indexed)",
        },
      },
      required: ["file", "line", "column"],
    },
  },
  {
    name: "canopy_get_docs",
    description: "Get documentation for a Canopy module or function.",
    inputSchema: {
      type: "object" as const,
      properties: {
        module: {
          type: "string",
          description: "Module name (e.g., 'List', 'Maybe', 'Html')",
        },
        function: {
          type: "string",
          description: "Function name within the module (optional)",
        },
      },
      required: ["module"],
    },
  },
  {
    name: "canopy_list_modules",
    description: "List all modules in a Canopy project.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description: "Path to the Canopy project directory (default: current directory)",
        },
      },
    },
  },
];

// Prompts for common Canopy tasks
const PROMPTS = [
  {
    name: "canopy_new_module",
    description: "Generate a new Canopy module with proper structure",
    arguments: [
      {
        name: "name",
        description: "Module name (e.g., 'Page.Home', 'Component.Button')",
        required: true,
      },
      {
        name: "type",
        description: "Module type: 'page', 'component', or 'utility'",
        required: false,
      },
    ],
  },
  {
    name: "canopy_tea_component",
    description: "Generate a Canopy TEA (The Elm Architecture) component",
    arguments: [
      {
        name: "name",
        description: "Component name",
        required: true,
      },
    ],
  },
  {
    name: "canopy_fix_error",
    description: "Help fix a Canopy compilation error",
    arguments: [
      {
        name: "error",
        description: "The error message from the compiler",
        required: true,
      },
    ],
  },
];

/**
 * Execute a shell command and return the output
 */
async function execCommand(
  command: string,
  args: string[],
  cwd?: string
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return new Promise((resolve) => {
    const proc = spawn(command, args, {
      cwd: cwd || process.cwd(),
      shell: false,
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    proc.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    proc.on("close", (code) => {
      resolve({
        stdout,
        stderr,
        exitCode: code ?? 1,
      });
    });
  });
}

/**
 * Find Canopy source files in a directory
 */
async function findCanopyFiles(dir: string): Promise<string[]> {
  const files: string[] = [];

  async function scan(currentDir: string) {
    const entries = await readdir(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = join(currentDir, entry.name);
      if (entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "node_modules") {
        await scan(fullPath);
      } else if (entry.isFile() && (entry.name.endsWith(".can") || entry.name.endsWith(".elm"))) {
        files.push(fullPath);
      }
    }
  }

  await scan(dir);
  return files;
}

/**
 * Extract module name from file content
 */
function extractModuleName(content: string): string | null {
  const match = content.match(/^module\s+([A-Z][A-Za-z0-9.]*)/m);
  return match ? match[1] : null;
}

/**
 * Create and start the MCP server
 */
async function main() {
  const server = new Server(
    {
      name: "canopy-mcp",
      version: "0.19.2",
    },
    {
      capabilities: {
        tools: {},
        resources: {},
        prompts: {},
      },
    }
  );

  // Handle tool listing
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOLS,
  }));

  // Handle tool execution
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    switch (name) {
      case "canopy_build": {
        const path = (args?.path as string) || ".";
        const optimize = args?.optimize as boolean;
        const output = args?.output as string;
        const format = args?.format as string;

        const cmdArgs = ["make", "src/Main.can"];
        if (optimize) cmdArgs.push("--optimize");
        if (output) cmdArgs.push(`--output=${output}`);
        if (format) cmdArgs.push(`--format=${format}`);

        const result = await execCommand("canopy", cmdArgs, path);

        return {
          content: [
            {
              type: "text",
              text:
                result.exitCode === 0
                  ? `Build successful!\n${result.stdout}`
                  : `Build failed:\n${result.stderr || result.stdout}`,
            },
          ],
          isError: result.exitCode !== 0,
        };
      }

      case "canopy_check": {
        const path = (args?.path as string) || ".";

        // Use canopy make with --output=/dev/null for type checking only
        const result = await execCommand(
          "canopy",
          ["make", "src/Main.can", "--output=/dev/null"],
          path
        );

        return {
          content: [
            {
              type: "text",
              text:
                result.exitCode === 0
                  ? "Type check passed! No errors found."
                  : `Type errors found:\n${result.stderr || result.stdout}`,
            },
          ],
          isError: result.exitCode !== 0,
        };
      }

      case "canopy_get_type": {
        return {
          content: [
            {
              type: "text",
              text: "Not yet implemented: type lookup at a specific location requires the Canopy Language Server (LSP), which is not yet available.\n\nWorkarounds:\n  - Run 'canopy make' to see type errors and inferred types\n  - Check the module's exposing list for type signatures\n  - Search for type annotations in the source file",
            },
          ],
          isError: true,
        };
      }

      case "canopy_find_definition": {
        return {
          content: [
            {
              type: "text",
              text: "Not yet implemented: go-to-definition requires the Canopy Language Server (LSP), which is not yet available.\n\nWorkarounds:\n  - Search for function definitions with grep or ripgrep\n  - Check import statements to find the source module\n  - Use 'canopy_list_modules' to find all modules in the project",
            },
          ],
          isError: true,
        };
      }

      case "canopy_get_docs": {
        const moduleName = args?.module as string;
        const funcName = args?.function as string | undefined;

        // Provide documentation for core modules
        const docs = getModuleDocs(moduleName, funcName);

        return {
          content: [
            {
              type: "text",
              text: docs,
            },
          ],
        };
      }

      case "canopy_list_modules": {
        const path = (args?.path as string) || ".";

        try {
          const files = await findCanopyFiles(path);
          const modules: string[] = [];

          for (const file of files) {
            const content = await readFile(file, "utf-8");
            const moduleName = extractModuleName(content);
            if (moduleName) {
              modules.push(`${moduleName} (${relative(path, file)})`);
            }
          }

          return {
            content: [
              {
                type: "text",
                text:
                  modules.length > 0
                    ? `Found ${modules.length} modules:\n\n${modules.join("\n")}`
                    : "No Canopy modules found in this directory.",
              },
            ],
          };
        } catch (error) {
          return {
            content: [
              {
                type: "text",
                text: `Error scanning for modules: ${error}`,
              },
            ],
            isError: true,
          };
        }
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  });

  // Handle resource listing
  server.setRequestHandler(ListResourcesRequestSchema, async () => ({
    resources: [
      {
        uri: "canopy://project/canopy.json",
        name: "Project Configuration",
        description: "Canopy project configuration file",
        mimeType: "application/json",
      },
      {
        uri: "canopy://docs/syntax",
        name: "Canopy Syntax Guide",
        description: "Quick reference for Canopy syntax",
        mimeType: "text/markdown",
      },
    ],
  }));

  // Handle resource reading
  server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    const { uri } = request.params;

    if (uri === "canopy://project/canopy.json") {
      try {
        const content = await readFile("canopy.json", "utf-8");
        return {
          contents: [{ uri, mimeType: "application/json", text: content }],
        };
      } catch {
        return {
          contents: [
            {
              uri,
              mimeType: "text/plain",
              text: "No canopy.json found in current directory",
            },
          ],
        };
      }
    }

    if (uri === "canopy://docs/syntax") {
      return {
        contents: [
          {
            uri,
            mimeType: "text/markdown",
            text: getSyntaxGuide(),
          },
        ],
      };
    }

    return {
      contents: [{ uri, mimeType: "text/plain", text: `Unknown resource: ${uri}` }],
    };
  });

  // Handle prompt listing
  server.setRequestHandler(ListPromptsRequestSchema, async () => ({
    prompts: PROMPTS,
  }));

  // Handle prompt execution
  server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    switch (name) {
      case "canopy_new_module": {
        const moduleName = args?.name || "NewModule";
        const moduleType = args?.type || "utility";
        return {
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: getNewModulePrompt(moduleName, moduleType),
              },
            },
          ],
        };
      }

      case "canopy_tea_component": {
        const componentName = args?.name || "Component";
        return {
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: getTeaComponentPrompt(componentName),
              },
            },
          ],
        };
      }

      case "canopy_fix_error": {
        const error = args?.error || "";
        return {
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: getFixErrorPrompt(error),
              },
            },
          ],
        };
      }

      default:
        return {
          messages: [
            {
              role: "user",
              content: { type: "text", text: `Unknown prompt: ${name}` },
            },
          ],
        };
    }
  });

  // Start the server with stdio transport
  const transport = new StdioServerTransport();
  await server.connect(transport);

  console.error("Canopy MCP server started");
}

/**
 * Get documentation for a module
 */
function getModuleDocs(moduleName: string, funcName?: string): string {
  const docs: Record<string, string> = {
    List: `# List Module

Lists are ordered sequences of values. All values in a list must have the same type.

## Common Functions

\`\`\`canopy
List.map : (a -> b) -> List a -> List b
List.filter : (a -> Bool) -> List a -> List a
List.foldr : (a -> b -> b) -> b -> List a -> b
List.head : List a -> Maybe a
List.length : List a -> Int
List.append : List a -> List a -> List a
\`\`\``,

    Maybe: `# Maybe Module

Represents values that may or may not exist. Use instead of null/undefined.

## Type
\`\`\`canopy
type Maybe a
    = Just a
    | Nothing
\`\`\`

## Common Functions

\`\`\`canopy
Maybe.map : (a -> b) -> Maybe a -> Maybe b
Maybe.withDefault : a -> Maybe a -> a
Maybe.andThen : (a -> Maybe b) -> Maybe a -> Maybe b
\`\`\``,

    Result: `# Result Module

Represents values that may be successful or contain an error.

## Type
\`\`\`canopy
type Result error value
    = Ok value
    | Err error
\`\`\`

## Common Functions

\`\`\`canopy
Result.map : (a -> b) -> Result x a -> Result x b
Result.withDefault : a -> Result x a -> a
Result.andThen : (a -> Result x b) -> Result x a -> Result x b
\`\`\``,

    Html: `# Html Module

Functions for building HTML views.

## Common Functions

\`\`\`canopy
Html.div : List (Attribute msg) -> List (Html msg) -> Html msg
Html.text : String -> Html msg
Html.button : List (Attribute msg) -> List (Html msg) -> Html msg
Html.input : List (Attribute msg) -> Html msg
\`\`\``,
  };

  const moduleDoc = docs[moduleName];
  if (!moduleDoc) {
    return `Documentation for '${moduleName}' not found in local cache.\n\nTry checking the official Canopy documentation at https://canopy-lang.org/docs`;
  }

  return moduleDoc;
}

/**
 * Get syntax guide
 */
function getSyntaxGuide(): string {
  return `# Canopy Syntax Quick Reference

## Functions

\`\`\`canopy
-- Type annotation
add : Int -> Int -> Int
add x y =
    x + y

-- Anonymous function
\\x -> x + 1
\`\`\`

## Control Flow

\`\`\`canopy
-- If expression
if condition then
    trueValue
else
    falseValue

-- Case expression
case value of
    Just x -> x
    Nothing -> default
\`\`\`

## Types

\`\`\`canopy
-- Type alias
type alias Model =
    { count : Int
    , name : String
    }

-- Custom type
type Msg
    = Increment
    | Decrement
    | SetName String
\`\`\`

## Operators

- \`++\` String concatenation
- \`|>\` Pipeline (forward)
- \`<|\` Pipeline (backward)
- \`::\` List cons
`;
}

/**
 * Get new module prompt
 */
function getNewModulePrompt(name: string, type: string): string {
  return `Create a new Canopy ${type} module named '${name}'.

Requirements:
- Follow Canopy naming conventions (PascalCase for modules)
- Include proper module declaration and exports
- Add type annotations for all public functions
- Include helpful comments for complex logic

The module should be ready to use with no TODO comments.`;
}

/**
 * Get TEA component prompt
 */
function getTeaComponentPrompt(name: string): string {
  return `Create a Canopy TEA (The Elm Architecture) component named '${name}'.

Include:
- Model type alias
- Msg type with appropriate variants
- init function
- update function with all Msg cases handled
- view function with proper HTML structure

Follow Canopy best practices:
- Use qualified imports
- Add type annotations
- Handle all cases exhaustively
- Use pipeline operators for data transformations`;
}

/**
 * Get fix error prompt
 */
function getFixErrorPrompt(error: string): string {
  return `Help fix this Canopy compilation error:

\`\`\`
${error}
\`\`\`

Analyze the error and provide:
1. What the error means
2. The likely cause
3. How to fix it with example code

Be specific to Canopy syntax and conventions.`;
}

// Run the server
main().catch(console.error);
