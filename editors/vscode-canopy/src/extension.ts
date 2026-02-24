/**
 * Canopy Language Extension for VS Code
 *
 * Provides full language support including:
 * - LSP integration for diagnostics, hover, completions, etc.
 * - Build and check commands
 * - Task integration
 * - Problem matchers for compiler output
 */

import * as vscode from 'vscode';
import { CanopyLanguageClient } from './lspClient';
import { CanopyTaskProvider } from './taskProvider';
import { CanopyCommands } from './commands';

let languageClient: CanopyLanguageClient | undefined;
let taskProvider: vscode.Disposable | undefined;

/**
 * Extension activation entry point.
 * Called when VS Code activates the extension (on first .can file open or workspace with canopy.json).
 */
export async function activate(context: vscode.ExtensionContext): Promise<void> {
    const outputChannel = vscode.window.createOutputChannel('Canopy');
    outputChannel.appendLine('Canopy extension activating...');

    try {
        languageClient = new CanopyLanguageClient(context, outputChannel);
        await languageClient.start();

        const canopyTaskProvider = new CanopyTaskProvider();
        taskProvider = vscode.tasks.registerTaskProvider('canopy', canopyTaskProvider);
        context.subscriptions.push(taskProvider);

        const commands = new CanopyCommands(languageClient, outputChannel, context.extensionUri);
        registerCommands(context, commands);

        registerStatusBarItem(context);

        outputChannel.appendLine('Canopy extension activated successfully');
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        outputChannel.appendLine(`Failed to activate Canopy extension: ${message}`);
        void vscode.window.showErrorMessage(`Canopy extension failed to activate: ${message}`);
    }
}

/**
 * Extension deactivation entry point.
 * Cleans up resources when the extension is deactivated.
 */
export async function deactivate(): Promise<void> {
    if (languageClient) {
        await languageClient.stop();
    }
}

/**
 * Register all extension commands with VS Code.
 */
function registerCommands(context: vscode.ExtensionContext, commands: CanopyCommands): void {
    const commandRegistrations = [
        vscode.commands.registerCommand('canopy.restartServer', () => void commands.restartServer()),
        vscode.commands.registerCommand('canopy.buildProject', () => void commands.buildProject()),
        vscode.commands.registerCommand('canopy.checkProject', () => void commands.checkProject()),
        vscode.commands.registerCommand('canopy.showServerOutput', () => commands.showServerOutput()),
        vscode.commands.registerCommand('canopy.initProject', () => void commands.initProject()),
        vscode.commands.registerCommand('canopy.installPackage', () => void commands.installPackage()),
        vscode.commands.registerCommand('canopy.openDebugger', () => commands.openDebugger()),
    ];

    context.subscriptions.push(...commandRegistrations);
}

/**
 * Create and register the status bar item showing Canopy server status.
 */
function registerStatusBarItem(context: vscode.ExtensionContext): void {
    const statusBarItem = vscode.window.createStatusBarItem(
        vscode.StatusBarAlignment.Left,
        100
    );

    statusBarItem.text = '$(leaf) Canopy';
    statusBarItem.tooltip = 'Canopy Language Server';
    statusBarItem.command = 'canopy.showServerOutput';
    statusBarItem.show();

    context.subscriptions.push(statusBarItem);

    vscode.window.onDidChangeActiveTextEditor((editor) => {
        if (editor && isCanopyFile(editor.document)) {
            statusBarItem.show();
        } else {
            statusBarItem.hide();
        }
    }, null, context.subscriptions);

    const activeEditor = vscode.window.activeTextEditor;
    if (activeEditor && isCanopyFile(activeEditor.document)) {
        statusBarItem.show();
    } else {
        statusBarItem.hide();
    }
}

/**
 * Check if a document is a Canopy source file.
 */
function isCanopyFile(document: vscode.TextDocument): boolean {
    return document.languageId === 'canopy' ||
           document.fileName.endsWith('.can') ||
           document.fileName.endsWith('.canopy');
}
