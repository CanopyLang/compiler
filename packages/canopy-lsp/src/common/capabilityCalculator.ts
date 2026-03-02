import {
  ClientCapabilities,
  ServerCapabilities,
  TextDocumentSyncKind,
} from "vscode-languageserver";
import { CommandManager } from "./commandManager";
import * as ElmMakeDiagnostics from "./providers/diagnostics/elmMakeDiagnostics";
import { semanticTokensLegend } from "./providers/semanticTokensProvider";

export class CapabilityCalculator {
  private clientCapabilities: ClientCapabilities;

  constructor(clientCapabilities: ClientCapabilities) {
    this.clientCapabilities = clientCapabilities;
  }

  get capabilities(): ServerCapabilities {
    this.clientCapabilities;

    return {
      codeActionProvider: {
        resolveProvider: true,
      },
      codeLensProvider: {
        resolveProvider: true,
      },
      completionProvider: {
        triggerCharacters: ["."],
      },
      definitionProvider: true,
      documentFormattingProvider: true,
      documentSymbolProvider: { label: "Canopy" },
      executeCommandProvider: {
        commands: [
          ElmMakeDiagnostics.CODE_ACTION_ELM_MAKE,
          ...CommandManager.commands,
        ],
      },
      foldingRangeProvider: true,
      hoverProvider: true,
      inlayHintProvider: true,
      referencesProvider: true,
      renameProvider: {
        prepareProvider: true,
      },
      selectionRangeProvider: true,
      semanticTokensProvider: {
        legend: semanticTokensLegend,
        full: true,
        range: true,
      },
      signatureHelpProvider: {
        triggerCharacters: [" "],
        retriggerCharacters: [" "],
      },
      textDocumentSync: TextDocumentSyncKind.Incremental,
      workspaceSymbolProvider: true,
      workspace: {
        fileOperations: {
          didCreate: {
            filters: [
              {
                scheme: "file",
                pattern: { glob: "**/*.{elm,can}", matches: "file" },
              },
            ],
          },
          willRename: {
            filters: [
              {
                scheme: "file",
                pattern: { glob: "**/*.{elm,can}", matches: "file" },
              },
              {
                scheme: "file",
                pattern: { glob: "**/", matches: "folder" },
              },
            ],
          },
          willDelete: {
            filters: [
              {
                scheme: "file",
                pattern: { glob: "**/*.{elm,can}", matches: "file" },
              },
            ],
          },
        },
      },
      linkedEditingRangeProvider: true,
    };
  }
}
