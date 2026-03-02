import { container } from "tsyringe";
import {
  Connection,
  SignatureHelp,
  SignatureHelpParams,
  SignatureInformation,
  ParameterInformation,
} from "vscode-languageserver";
import { URI } from "vscode-uri";
import { SyntaxNode } from "web-tree-sitter";
import { DiagnosticsProvider } from ".";
import { ElmWorkspaceMatcher } from "../util/elmWorkspaceMatcher";
import { TreeUtils } from "../util/treeUtils";
import { ISourceFile } from "../../compiler/forest";
import { TypeChecker } from "../../compiler/typeChecker";
import { IProgram } from "../../compiler/program";
import { Type, TFunction } from "../../compiler/typeInference";

export type ISignatureHelpParams = SignatureHelpParams & {
  program: IProgram;
  sourceFile: ISourceFile;
};

/**
 * Provides signature help (parameter info) when a user is typing function
 * arguments. Shows the function's type signature with the active parameter
 * highlighted so the developer knows what argument is expected next.
 */
export class SignatureHelpProvider {
  private connection: Connection;
  private diagnostics: DiagnosticsProvider;

  constructor() {
    this.connection = container.resolve<Connection>("Connection");
    this.diagnostics = container.resolve(DiagnosticsProvider);
    this.connection.onSignatureHelp(
      this.diagnostics.interruptDiagnostics(() =>
        new ElmWorkspaceMatcher((params: SignatureHelpParams) =>
          URI.parse(params.textDocument.uri),
        ).handle(this.handleSignatureHelpRequest.bind(this)),
      ),
    );
  }

  protected handleSignatureHelpRequest = (
    params: ISignatureHelpParams,
  ): SignatureHelp | null => {
    const sourceFile = params.sourceFile;

    if (!sourceFile) {
      return null;
    }

    const checker = params.program.getTypeChecker();
    const tree = sourceFile.tree;

    // Find the node at the cursor position
    const nodeAtPosition = TreeUtils.getNamedDescendantForPosition(
      tree.rootNode,
      params.position,
    );

    // Walk up to find if we're inside a function call expression
    const callInfo = this.findEnclosingFunctionCall(nodeAtPosition);
    if (!callInfo) {
      return null;
    }

    const { functionNode, activeParameterIndex } = callInfo;

    // Get the function definition's type
    const definitionResult = checker.findDefinition(functionNode, sourceFile);
    if (!definitionResult.symbol) {
      return null;
    }

    const funcType = checker.findType(definitionResult.symbol.node);
    const typeString = checker.typeToString(funcType, sourceFile);

    if (!typeString || typeString === "unknown") {
      return null;
    }

    const parameters = this.extractParameters(funcType, checker, sourceFile);
    const funcName = functionNode.text;

    const signature: SignatureInformation = {
      label: `${funcName} : ${typeString}`,
      parameters: parameters.map(
        (p): ParameterInformation => ({
          label: p,
        }),
      ),
      activeParameter: activeParameterIndex,
    };

    return {
      signatures: [signature],
      activeSignature: 0,
      activeParameter: activeParameterIndex,
    };
  };

  /**
   * Walk up the syntax tree to find the enclosing function_call_expr and
   * determine which argument position the cursor is at.
   */
  private findEnclosingFunctionCall(
    node: SyntaxNode,
  ): { functionNode: SyntaxNode; activeParameterIndex: number } | null {
    let current: SyntaxNode | null = node;

    while (current) {
      if (current.type === "function_call_expr") {
        const funcNode = current.firstNamedChild;
        if (!funcNode) {
          return null;
        }

        // Count argument positions before our node
        let argIndex = 0;
        for (let i = 1; i < current.namedChildCount; i++) {
          const arg = current.namedChild(i);
          if (arg && node.startIndex >= arg.startIndex) {
            argIndex = i - 1;
          }
        }

        return {
          functionNode: funcNode,
          activeParameterIndex: argIndex,
        };
      }
      current = current.parent;
    }

    return null;
  }

  /**
   * Extract parameter type strings from a function type.
   */
  private extractParameters(
    funcType: Type,
    checker: TypeChecker,
    sourceFile: ISourceFile,
  ): string[] {
    const params: string[] = [];
    let current = funcType;

    while (isTFunction(current)) {
      params.push(checker.typeToString(current.params[0], sourceFile));
      current = current.return;
    }

    return params;
  }
}

/**
 * Type guard for TFunction.
 */
function isTFunction(t: Type): t is TFunction {
  return (
    t !== undefined &&
    typeof t === "object" &&
    "nodeType" in t &&
    t.nodeType === "Function"
  );
}
