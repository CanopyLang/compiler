/**
 * Language Server Protocol client for Canopy.
 *
 * Manages the connection to the canopy-language-server executable,
 * handling lifecycle, configuration, and communication.
 */

import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind,
    State,
} from 'vscode-languageclient/node';

/** Configuration keys for the Canopy extension */
interface CanopyConfig {
    serverPath: string;
    serverArgs: string[];
    trace: 'off' | 'messages' | 'verbose';
}

/**
 * Manages the Canopy Language Server connection.
 */
export class CanopyLanguageClient {
    private client: LanguageClient | undefined;
    private readonly context: vscode.ExtensionContext;
    private readonly outputChannel: vscode.OutputChannel;
    private statusBarItem: vscode.StatusBarItem | undefined;

    constructor(context: vscode.ExtensionContext, outputChannel: vscode.OutputChannel) {
        this.context = context;
        this.outputChannel = outputChannel;
    }

    /**
     * Start the language server client.
     */
    async start(): Promise<void> {
        const config = this.getConfiguration();
        const serverPath = this.resolveServerPath(config.serverPath);

        if (!serverPath) {
            this.outputChannel.appendLine('canopy-language-server not found. LSP features will be disabled.');
            this.showServerNotFoundWarning();
            return;
        }

        this.outputChannel.appendLine(`Starting canopy-language-server from: ${serverPath}`);

        const serverOptions: ServerOptions = {
            run: {
                command: serverPath,
                args: config.serverArgs,
                transport: TransportKind.stdio,
            },
            debug: {
                command: serverPath,
                args: [...config.serverArgs, '--debug'],
                transport: TransportKind.stdio,
            },
        };

        const clientOptions: LanguageClientOptions = {
            documentSelector: [
                { scheme: 'file', language: 'canopy' },
                { scheme: 'file', language: 'elm' },
                { scheme: 'untitled', language: 'canopy' },
                { scheme: 'untitled', language: 'elm' },
            ],
            synchronize: {
                fileEvents: [
                    vscode.workspace.createFileSystemWatcher('**/*.can'),
                    vscode.workspace.createFileSystemWatcher('**/*.canopy'),
                    vscode.workspace.createFileSystemWatcher('**/*.elm'),
                    vscode.workspace.createFileSystemWatcher('**/canopy.json'),
                    vscode.workspace.createFileSystemWatcher('**/elm.json'),
                ],
            },
            outputChannel: this.outputChannel,
            traceOutputChannel: this.outputChannel,
            initializationOptions: this.getInitializationOptions(),
            middleware: {
                provideCompletionItem: async (document, position, context, token, next) => {
                    const result = await next(document, position, context, token);
                    return result;
                },
            },
        };

        this.client = new LanguageClient(
            'canopy',
            'Canopy Language Server',
            serverOptions,
            clientOptions
        );

        this.registerClientEventHandlers();

        await this.client.start();
        this.outputChannel.appendLine('Language server started successfully');
    }

    /**
     * Stop the language server client.
     */
    async stop(): Promise<void> {
        if (this.client) {
            await this.client.stop();
            this.client = undefined;
        }
    }

    /**
     * Restart the language server.
     */
    async restart(): Promise<void> {
        this.outputChannel.appendLine('Restarting language server...');
        await this.stop();
        await this.start();
    }

    /**
     * Check if the language server is running.
     */
    isRunning(): boolean {
        return this.client !== undefined && this.client.state === State.Running;
    }

    /**
     * Get the underlying LanguageClient instance.
     */
    getClient(): LanguageClient | undefined {
        return this.client;
    }

    /**
     * Get configuration options for the language server.
     */
    private getConfiguration(): CanopyConfig {
        const config = vscode.workspace.getConfiguration('canopy');
        return {
            serverPath: config.get<string>('serverPath', ''),
            serverArgs: config.get<string[]>('serverArgs', []),
            trace: config.get<'off' | 'messages' | 'verbose'>('trace.server', 'off'),
        };
    }

    /**
     * Resolve the full path to the language server executable.
     * Searches in the following order:
     * 1. User-configured path from settings
     * 2. Bundled server in packages/canopy-lsp (monorepo integration)
     * 3. Local project .canopy/bin directory
     * 4. Global npm installation
     * 5. System PATH
     */
    private resolveServerPath(configuredPath: string): string | undefined {
        if (configuredPath) {
            return configuredPath;
        }

        const bundledServerPaths = [
            path.join(this.context.extensionPath, '..', '..', 'packages', 'canopy-lsp', 'out', 'node', 'index.js'),
            path.join(this.context.extensionPath, '..', 'packages', 'canopy-lsp', 'out', 'node', 'index.js'),
        ];

        for (const bundledPath of bundledServerPaths) {
            if (this.fileExistsReadable(bundledPath)) {
                this.outputChannel.appendLine(`Found bundled language server at: ${bundledPath}`);
                return bundledPath;
            }
        }

        const npmGlobalPaths = [
            path.join(process.env.HOME || '', '.npm-global', 'lib', 'node_modules', '@canopy-lang', 'canopy-language-server', 'out', 'node', 'index.js'),
            path.join('/usr', 'local', 'lib', 'node_modules', '@canopy-lang', 'canopy-language-server', 'out', 'node', 'index.js'),
        ];

        for (const npmPath of npmGlobalPaths) {
            if (this.fileExistsReadable(npmPath)) {
                this.outputChannel.appendLine(`Found npm-installed language server at: ${npmPath}`);
                return npmPath;
            }
        }

        const possibleNames = [
            'canopy-language-server',
            'canopy-lsp',
        ];

        for (const name of possibleNames) {
            const resolved = this.findExecutableInPath(name);
            if (resolved) {
                return resolved;
            }
        }

        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (workspaceFolder) {
            const localServerPaths = [
                path.join(workspaceFolder.uri.fsPath, '.canopy', 'bin', 'canopy-language-server'),
                path.join(workspaceFolder.uri.fsPath, 'node_modules', '@canopy-lang', 'canopy-language-server', 'out', 'node', 'index.js'),
                path.join(workspaceFolder.uri.fsPath, 'node_modules', '.bin', 'canopy-language-server'),
            ];

            for (const localPath of localServerPaths) {
                if (this.fileExistsReadable(localPath)) {
                    this.outputChannel.appendLine(`Found local language server at: ${localPath}`);
                    return localPath;
                }
            }
        }

        return undefined;
    }

    /**
     * Check if a file exists and is readable (for Node.js scripts).
     */
    private fileExistsReadable(filePath: string): boolean {
        try {
            fs.accessSync(filePath, fs.constants.R_OK);
            return true;
        } catch {
            return false;
        }
    }

    /**
     * Find an executable in the system PATH.
     */
    private findExecutableInPath(name: string): string | undefined {
        const pathEnv = process.env.PATH || '';
        const pathSeparator = process.platform === 'win32' ? ';' : ':';
        const executableExtensions = process.platform === 'win32' ? ['.exe', '.cmd', '.bat', ''] : [''];

        for (const dir of pathEnv.split(pathSeparator)) {
            for (const ext of executableExtensions) {
                const fullPath = path.join(dir, name + ext);
                if (this.fileExists(fullPath)) {
                    return fullPath;
                }
            }
        }

        return undefined;
    }

    /**
     * Check if a file exists synchronously.
     */
    private fileExists(filePath: string): boolean {
        try {
            fs.accessSync(filePath, fs.constants.X_OK);
            return true;
        } catch {
            return false;
        }
    }

    /**
     * Get initialization options to send to the language server.
     */
    private getInitializationOptions(): Record<string, unknown> {
        const config = vscode.workspace.getConfiguration('canopy');
        return {
            diagnostics: {
                enable: config.get<boolean>('diagnostics.enable', true),
            },
            format: {
                enable: config.get<boolean>('format.enable', true),
            },
            hover: {
                enable: config.get<boolean>('hover.enable', true),
            },
        };
    }

    /**
     * Register event handlers for client state changes.
     */
    private registerClientEventHandlers(): void {
        if (!this.client) {
            return;
        }

        this.client.onDidChangeState((event) => {
            switch (event.newState) {
                case State.Running:
                    this.outputChannel.appendLine('Language server is running');
                    this.updateStatusBar('running');
                    break;
                case State.Starting:
                    this.outputChannel.appendLine('Language server is starting...');
                    this.updateStatusBar('starting');
                    break;
                case State.Stopped:
                    this.outputChannel.appendLine('Language server stopped');
                    this.updateStatusBar('stopped');
                    break;
            }
        });
    }

    /**
     * Update the status bar to reflect server state.
     */
    private updateStatusBar(state: 'running' | 'starting' | 'stopped'): void {
        if (!this.statusBarItem) {
            this.statusBarItem = vscode.window.createStatusBarItem(
                vscode.StatusBarAlignment.Right,
                100
            );
            this.context.subscriptions.push(this.statusBarItem);
        }

        switch (state) {
            case 'running':
                this.statusBarItem.text = '$(check) Canopy LSP';
                this.statusBarItem.tooltip = 'Canopy Language Server is running';
                this.statusBarItem.backgroundColor = undefined;
                break;
            case 'starting':
                this.statusBarItem.text = '$(sync~spin) Canopy LSP';
                this.statusBarItem.tooltip = 'Canopy Language Server is starting...';
                this.statusBarItem.backgroundColor = undefined;
                break;
            case 'stopped':
                this.statusBarItem.text = '$(warning) Canopy LSP';
                this.statusBarItem.tooltip = 'Canopy Language Server is stopped';
                this.statusBarItem.backgroundColor = new vscode.ThemeColor(
                    'statusBarItem.warningBackground'
                );
                break;
        }

        this.statusBarItem.show();
    }

    /**
     * Show a warning when the language server is not found.
     */
    private showServerNotFoundWarning(): void {
        const message = 'Canopy Language Server not found. Install it or configure the path in settings.';
        const installAction = 'Install Instructions';
        const configureAction = 'Configure Path';

        void vscode.window.showWarningMessage(message, installAction, configureAction).then((action) => {
            if (action === installAction) {
                void vscode.env.openExternal(
                    vscode.Uri.parse('https://github.com/canopy-lang/canopy#installation')
                );
            } else if (action === configureAction) {
                void vscode.commands.executeCommand(
                    'workbench.action.openSettings',
                    'canopy.serverPath'
                );
            }
        });
    }
}
