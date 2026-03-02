import { container } from "tsyringe";
import {
  Connection,
  SemanticTokens,
  SemanticTokensBuilder,
  SemanticTokensLegend,
  SemanticTokensParams,
  SemanticTokensRangeParams,
} from "vscode-languageserver";
import { URI } from "vscode-uri";
import { SyntaxNode } from "web-tree-sitter";
import { DiagnosticsProvider } from ".";
import { ElmWorkspaceMatcher } from "../util/elmWorkspaceMatcher";
import { ISourceFile } from "../../compiler/forest";
import { IProgram } from "../../compiler/program";

export type ISemanticTokensParams = SemanticTokensParams & {
  program: IProgram;
  sourceFile: ISourceFile;
};

/** Token types for semantic highlighting. */
const tokenTypes = [
  "namespace", // module names
  "type", // type names (custom types, type aliases)
  "typeParameter", // type variables (a, b, comparable, etc.)
  "function", // function names
  "variable", // local variables and parameters
  "keyword", // language keywords
  "string", // string literals
  "number", // numeric literals
  "operator", // operators (+, -, |>, etc.)
  "property", // record field names
  "enumMember", // union constructors (Just, Nothing, Ok, etc.)
  "comment", // comments
  "macro", // port declarations
] as const;

/** Token modifiers for additional classification. */
const tokenModifiers = [
  "declaration",
  "definition",
  "readonly",
  "modification",
  "documentation",
  "defaultLibrary",
] as const;

/** Semantic tokens legend, exported so capability registration can reference it. */
export const semanticTokensLegend: SemanticTokensLegend = {
  tokenTypes: [...tokenTypes],
  tokenModifiers: [...tokenModifiers],
};

type TokenType = (typeof tokenTypes)[number];

/**
 * Provides semantic token information for rich syntax highlighting. Rather than
 * relying solely on TextMate grammars (which are regex-based), semantic tokens
 * use the parsed AST to classify tokens accurately, enabling coloring of type
 * variables differently from regular variables, constructors differently from
 * functions, and module names differently from identifiers.
 */
export class SemanticTokensProvider {
  private connection: Connection;
  private diagnostics: DiagnosticsProvider;

  constructor() {
    this.connection = container.resolve<Connection>("Connection");
    this.diagnostics = container.resolve(DiagnosticsProvider);

    this.connection.languages.semanticTokens.on(
      this.diagnostics.interruptDiagnostics(() =>
        new ElmWorkspaceMatcher((params: SemanticTokensParams) =>
          URI.parse(params.textDocument.uri),
        ).handle(this.handleSemanticTokensFull.bind(this)),
      ),
    );

    this.connection.languages.semanticTokens.onRange(
      this.diagnostics.interruptDiagnostics(() =>
        new ElmWorkspaceMatcher((params: SemanticTokensRangeParams) =>
          URI.parse(params.textDocument.uri),
        ).handle(this.handleSemanticTokensRange.bind(this)),
      ),
    );
  }

  protected handleSemanticTokensFull = (
    params: ISemanticTokensParams,
  ): SemanticTokens => {
    const builder = new SemanticTokensBuilder();
    const sourceFile = params.sourceFile;

    if (sourceFile) {
      this.walkTree(sourceFile.tree.rootNode, builder);
    }

    return builder.build();
  };

  protected handleSemanticTokensRange = (
    params: SemanticTokensRangeParams & {
      program: IProgram;
      sourceFile: ISourceFile;
    },
  ): SemanticTokens => {
    const builder = new SemanticTokensBuilder();
    const sourceFile = params.sourceFile;

    if (sourceFile) {
      const { range } = params;
      this.walkTree(sourceFile.tree.rootNode, builder, range);
    }

    return builder.build();
  };

  /**
   * Walk the syntax tree and push semantic tokens to the builder.
   */
  private walkTree(
    node: SyntaxNode,
    builder: SemanticTokensBuilder,
    range?: { start: { line: number; character: number }; end: { line: number; character: number } },
  ): void {
    // If a range is given, skip nodes that fall entirely outside
    if (range && !this.nodeIntersectsRange(node, range)) {
      return;
    }

    const tokenType = this.classifyNode(node);
    if (tokenType !== null && node.text.length > 0) {
      const modifierBits = this.getModifierBits(node);
      const typeIndex = tokenTypes.indexOf(tokenType);
      if (typeIndex >= 0) {
        builder.push(
          node.startPosition.row,
          node.startPosition.column,
          node.text.length,
          typeIndex,
          modifierBits,
        );
      }
    }

    // Recurse into children
    for (let i = 0; i < node.childCount; i++) {
      const child = node.child(i);
      if (child) {
        this.walkTree(child, builder, range);
      }
    }
  }

  /**
   * Classify a syntax node into a semantic token type based on tree-sitter node type.
   */
  private classifyNode(node: SyntaxNode): TokenType | null {
    switch (node.type) {
      // Module names
      case "upper_case_qid":
        if (this.isModuleReference(node)) {
          return "namespace";
        }
        return null;

      case "module_declaration":
      case "import_clause":
        return null; // Don't color the whole node, only children

      // Type names
      case "upper_case_identifier":
        if (this.isTypeContext(node)) {
          return "type";
        }
        if (this.isConstructorContext(node)) {
          return "enumMember";
        }
        return null;

      // Type variables
      case "type_variable":
        return "typeParameter";

      // Function names in declarations
      case "lower_case_identifier":
        if (this.isFunctionDeclaration(node)) {
          return "function";
        }
        if (this.isFieldAccess(node)) {
          return "property";
        }
        return "variable";

      // Record field names
      case "field":
        return "property";
      case "field_type":
        return null; // Will be handled by children

      // String literals
      case "string_constant_expr":
      case "open_char":
      case "close_char":
      case "regular_string_part":
        return "string";

      // Numeric literals
      case "number_constant_expr":
      case "number_literal":
        return "number";

      // Operators
      case "operator_identifier":
      case "operator":
        return "operator";

      // Port keyword
      case "port":
        return "macro";

      // Comments
      case "line_comment":
      case "block_comment":
        return "comment";

      default:
        return null;
    }
  }

  /**
   * Determine modifier bits for a node.
   */
  private getModifierBits(node: SyntaxNode): number {
    let bits = 0;

    // Check if it's a declaration
    if (this.isFunctionDeclaration(node)) {
      bits |= 1 << tokenModifiers.indexOf("declaration");
      bits |= 1 << tokenModifiers.indexOf("definition");
    }

    return bits;
  }

  /**
   * Check if a node is a module name reference (e.g., `List.map`, `Maybe.withDefault`).
   */
  private isModuleReference(node: SyntaxNode): boolean {
    const parent = node.parent;
    return (
      parent?.type === "module_declaration" ||
      parent?.type === "import_clause" ||
      parent?.type === "as_clause" ||
      node.text.includes(".")
    );
  }

  /**
   * Check if an upper_case_identifier is in a type context.
   */
  private isTypeContext(node: SyntaxNode): boolean {
    const parent = node.parent;
    if (!parent) return false;

    return (
      parent.type === "type_declaration" ||
      parent.type === "type_alias_declaration" ||
      parent.type === "type_ref" ||
      parent.type === "type_expression" ||
      parent.type === "type_annotation"
    );
  }

  /**
   * Check if an upper_case_identifier is a union constructor.
   */
  private isConstructorContext(node: SyntaxNode): boolean {
    const parent = node.parent;
    if (!parent) return false;

    return (
      parent.type === "union_variant" ||
      parent.type === "value_expr" ||
      parent.type === "union_pattern" ||
      parent.type === "exposing_list" ||
      parent.type === "exposed_type"
    );
  }

  /**
   * Check if a lower_case_identifier is a function declaration.
   */
  private isFunctionDeclaration(node: SyntaxNode): boolean {
    const parent = node.parent;
    return (
      parent?.type === "function_declaration_left" &&
      parent?.firstChild === node
    );
  }

  /**
   * Check if a lower_case_identifier is a record field access.
   */
  private isFieldAccess(node: SyntaxNode): boolean {
    const parent = node.parent;
    return (
      parent?.type === "field_access_expr" ||
      parent?.type === "field_accessor_function_expr" ||
      parent?.type === "field"
    );
  }

  /**
   * Check if a node intersects a given range.
   */
  private nodeIntersectsRange(
    node: SyntaxNode,
    range: { start: { line: number; character: number }; end: { line: number; character: number } },
  ): boolean {
    return (
      node.startPosition.row <= range.end.line &&
      node.endPosition.row >= range.start.line
    );
  }
}
