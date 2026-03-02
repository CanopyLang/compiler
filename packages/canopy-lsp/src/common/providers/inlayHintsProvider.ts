import { container } from "tsyringe";
import {
  Connection,
  InlayHint,
  InlayHintKind,
  InlayHintParams,
} from "vscode-languageserver";
import { URI } from "vscode-uri";
import { SyntaxNode } from "web-tree-sitter";
import { DiagnosticsProvider } from ".";
import { ElmWorkspaceMatcher } from "../util/elmWorkspaceMatcher";
import { TreeUtils } from "../util/treeUtils";
import { ISourceFile } from "../../compiler/forest";
import { TypeChecker } from "../../compiler/typeChecker";
import { IProgram } from "../../compiler/program";

export type IInlayHintParams = InlayHintParams & {
  program: IProgram;
  sourceFile: ISourceFile;
};

/**
 * Provides inline type hints for unannotated function definitions and
 * top-level declarations. Shows inferred return types and parameter types
 * so developers can see type information without explicit annotations.
 */
export class InlayHintsProvider {
  private connection: Connection;
  private diagnostics: DiagnosticsProvider;

  constructor() {
    this.connection = container.resolve<Connection>("Connection");
    this.diagnostics = container.resolve(DiagnosticsProvider);
    this.connection.languages.inlayHint.on(
      this.diagnostics.interruptDiagnostics(() =>
        new ElmWorkspaceMatcher((params: InlayHintParams) =>
          URI.parse(params.textDocument.uri),
        ).handle(this.handleInlayHintRequest.bind(this)),
      ),
    );
  }

  protected handleInlayHintRequest = (
    params: IInlayHintParams,
  ): InlayHint[] => {
    const hints: InlayHint[] = [];
    const sourceFile = params.sourceFile;

    if (!sourceFile) {
      return hints;
    }

    const checker = params.program.getTypeChecker();
    const tree = sourceFile.tree;

    // Find all value declarations (function definitions)
    const declarations = tree.rootNode.descendantsOfType("value_declaration");

    for (const declaration of declarations) {
      this.addHintsForDeclaration(declaration, checker, sourceFile, hints);
    }

    return hints;
  };

  /**
   * Adds inlay hints for a single value declaration if it lacks a type annotation.
   */
  private addHintsForDeclaration(
    declaration: SyntaxNode,
    checker: TypeChecker,
    sourceFile: ISourceFile,
    hints: InlayHint[],
  ): void {
    // Check if the declaration already has a type annotation
    if (this.hasTypeAnnotation(declaration)) {
      return;
    }

    const functionDecLeft = declaration.childForFieldName("functionDeclarationLeft")
      ?? TreeUtils.findFirstNamedChildOfType("function_declaration_left", declaration);

    if (!functionDecLeft) {
      return;
    }

    // Get the function name node
    const nameNode = functionDecLeft.firstNamedChild;
    if (!nameNode) {
      return;
    }

    // Infer the type
    const inferredType = checker.findType(declaration);
    const typeString = checker.typeToString(inferredType, sourceFile);

    // Skip if we got an unknown type
    if (!typeString || typeString === "unknown") {
      return;
    }

    // Add return type hint after the function name and parameters
    const equalsSign = this.findEquals(declaration);
    if (equalsSign) {
      hints.push({
        position: {
          line: equalsSign.startPosition.row,
          character: equalsSign.startPosition.column,
        },
        label: `: ${typeString} `,
        kind: InlayHintKind.Type,
        paddingLeft: true,
        paddingRight: true,
      });
    }
  }

  /**
   * Checks whether the given value_declaration has a preceding type_annotation.
   */
  private hasTypeAnnotation(declaration: SyntaxNode): boolean {
    const prev = declaration.previousNamedSibling;
    return prev?.type === "type_annotation";
  }

  /**
   * Finds the '=' token in a value declaration.
   */
  private findEquals(declaration: SyntaxNode): SyntaxNode | null {
    for (let i = 0; i < declaration.childCount; i++) {
      const child = declaration.child(i);
      if (child && child.type === "eq") {
        return child;
      }
    }
    return null;
  }
}
