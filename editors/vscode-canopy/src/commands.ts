/**
 * Command implementations for the Canopy VS Code extension.
 *
 * Provides commands for building, checking, and managing the language server.
 */

import * as vscode from 'vscode';
import * as childProcess from 'child_process';
import { CanopyLanguageClient } from './lspClient';
import { CanopyDebuggerPanel } from './debugger';

/**
 * Implements all Canopy extension commands.
 */
export class CanopyCommands {
    private readonly client: CanopyLanguageClient;
    private readonly outputChannel: vscode.OutputChannel;
    private readonly extensionUri: vscode.Uri;

    constructor(
        client: CanopyLanguageClient,
        outputChannel: vscode.OutputChannel,
        extensionUri?: vscode.Uri
    ) {
        this.client = client;
        this.outputChannel = outputChannel;
        this.extensionUri = extensionUri || vscode.Uri.file('');
    }

    /**
     * Open the Canopy Debugger panel.
     */
    openDebugger(): void {
        CanopyDebuggerPanel.createOrShow(this.extensionUri);
    }

    /**
     * Restart the language server.
     */
    async restartServer(): Promise<void> {
        try {
            await vscode.window.withProgress(
                {
                    location: vscode.ProgressLocation.Notification,
                    title: 'Restarting Canopy Language Server...',
                    cancellable: false,
                },
                async () => {
                    await this.client.restart();
                }
            );

            void vscode.window.showInformationMessage('Canopy Language Server restarted');
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            void vscode.window.showErrorMessage(`Failed to restart language server: ${message}`);
        }
    }

    /**
     * Build the current Canopy project.
     */
    async buildProject(): Promise<void> {
        const workspaceFolder = this.getWorkspaceFolder();
        if (!workspaceFolder) {
            return;
        }

        const config = vscode.workspace.getConfiguration('canopy');
        const optimize = config.get<boolean>('compiler.optimize', false);
        const outputDir = config.get<string>('compiler.outputDirectory', 'build');

        const args = ['make', '--output', outputDir];
        if (optimize) {
            args.push('--optimize');
        }

        await this.runCompilerCommand(args, 'Building project...', workspaceFolder);
    }

    /**
     * Type-check the current Canopy project without generating output.
     */
    async checkProject(): Promise<void> {
        const workspaceFolder = this.getWorkspaceFolder();
        if (!workspaceFolder) {
            return;
        }

        await this.runCompilerCommand(['check'], 'Checking project...', workspaceFolder);
    }

    /**
     * Show the language server output channel.
     */
    showServerOutput(): void {
        this.outputChannel.show();
    }

    /**
     * Initialize a new Canopy project in the current workspace.
     */
    async initProject(): Promise<void> {
        const workspaceFolder = this.getWorkspaceFolder();
        if (!workspaceFolder) {
            return;
        }

        const canopyJsonExists = await this.fileExists(
            vscode.Uri.joinPath(workspaceFolder.uri, 'canopy.json')
        );

        if (canopyJsonExists) {
            const overwrite = await vscode.window.showWarningMessage(
                'canopy.json already exists. Reinitialize project?',
                'Yes',
                'No'
            );

            if (overwrite !== 'Yes') {
                return;
            }
        }

        await this.runCompilerCommand(['init'], 'Initializing project...', workspaceFolder);
    }

    /**
     * Install a package into the current project.
     */
    async installPackage(): Promise<void> {
        const workspaceFolder = this.getWorkspaceFolder();
        if (!workspaceFolder) {
            return;
        }

        const packageName = await vscode.window.showInputBox({
            prompt: 'Enter package name (e.g., canopy/html)',
            placeHolder: 'author/package',
            validateInput: (value) => {
                if (!value) {
                    return 'Package name is required';
                }
                if (!value.includes('/')) {
                    return 'Package name must be in format author/package';
                }
                return undefined;
            },
        });

        if (!packageName) {
            return;
        }

        await this.runCompilerCommand(
            ['install', packageName],
            `Installing ${packageName}...`,
            workspaceFolder
        );
    }

    /**
     * Get the current workspace folder, showing an error if none is open.
     */
    private getWorkspaceFolder(): vscode.WorkspaceFolder | undefined {
        const workspaceFolders = vscode.workspace.workspaceFolders;

        if (!workspaceFolders || workspaceFolders.length === 0) {
            void vscode.window.showErrorMessage('No workspace folder is open');
            return undefined;
        }

        if (workspaceFolders.length === 1) {
            return workspaceFolders[0];
        }

        return workspaceFolders[0];
    }

    /**
     * Run a canopy compiler command with progress notification.
     */
    private async runCompilerCommand(
        args: string[],
        progressTitle: string,
        workspaceFolder: vscode.WorkspaceFolder
    ): Promise<void> {
        const compilerPath = this.getCompilerPath();

        await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: progressTitle,
                cancellable: true,
            },
            async (_progress, token) => {
                return new Promise<void>((resolve, reject) => {
                    const proc = childProcess.spawn(compilerPath, args, {
                        cwd: workspaceFolder.uri.fsPath,
                        shell: true,
                    });

                    proc.stdout.on('data', (data: Buffer) => {
                        const text = data.toString();
                        this.outputChannel.append(text);
                    });

                    proc.stderr.on('data', (data: Buffer) => {
                        const text = data.toString();
                        this.outputChannel.append(text);
                    });

                    proc.on('close', (code: number | null) => {
                        if (code === 0) {
                            void vscode.window.showInformationMessage(
                                `Canopy: ${args[0]} completed successfully`
                            );
                            resolve();
                        } else {
                            void vscode.window.showErrorMessage(
                                `Canopy: ${args[0]} failed with exit code ${code ?? 'unknown'}`
                            );
                            this.outputChannel.show();
                            reject(new Error(`Command failed with exit code ${code ?? 'unknown'}`));
                        }
                    });

                    proc.on('error', (error: Error) => {
                        void vscode.window.showErrorMessage(`Failed to run canopy: ${error.message}`);
                        reject(error);
                    });

                    token.onCancellationRequested(() => {
                        proc.kill();
                        reject(new Error('Operation cancelled'));
                    });
                });
            }
        );
    }

    /**
     * Get the path to the Canopy compiler.
     */
    private getCompilerPath(): string {
        const config = vscode.workspace.getConfiguration('canopy');
        const configuredPath = config.get<string>('compiler.path', '');

        if (configuredPath) {
            return configuredPath;
        }

        return 'canopy';
    }

    /**
     * Check if a file exists.
     */
    private async fileExists(uri: vscode.Uri): Promise<boolean> {
        try {
            await vscode.workspace.fs.stat(uri);
            return true;
        } catch {
            return false;
        }
    }
}
