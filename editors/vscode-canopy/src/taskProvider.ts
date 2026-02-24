/**
 * Task Provider for Canopy build tasks.
 *
 * Provides task definitions for common Canopy operations like building,
 * checking, and running the REPL.
 */

import * as vscode from 'vscode';
import * as path from 'path';

/** Task definition for Canopy tasks */
interface CanopyTaskDefinition extends vscode.TaskDefinition {
    command: string;
    file?: string;
    output?: string;
    optimize?: boolean;
}

/**
 * Provides Canopy build tasks to VS Code's task system.
 */
export class CanopyTaskProvider implements vscode.TaskProvider {
    static readonly taskType = 'canopy';

    /**
     * Provide available tasks when the user requests task discovery.
     */
    provideTasks(): vscode.ProviderResult<vscode.Task[]> {
        return this.getAvailableTasks();
    }

    /**
     * Resolve a task definition into an executable task.
     */
    resolveTask(task: vscode.Task): vscode.ProviderResult<vscode.Task> {
        const definition = task.definition as CanopyTaskDefinition;

        if (definition.command) {
            return this.createTask(definition);
        }

        return undefined;
    }

    /**
     * Get all available default tasks.
     */
    private getAvailableTasks(): vscode.Task[] {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            return [];
        }

        return [
            this.createBuildTask(workspaceFolder),
            this.createBuildOptimizedTask(workspaceFolder),
            this.createCheckTask(workspaceFolder),
            this.createReplTask(workspaceFolder),
            this.createWatchTask(workspaceFolder),
        ];
    }

    /**
     * Create a task from a task definition.
     */
    private createTask(definition: CanopyTaskDefinition): vscode.Task {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        const args = this.buildCommandArgs(definition);
        const compilerPath = this.getCompilerPath();

        const execution = new vscode.ShellExecution(compilerPath, args, {
            cwd: workspaceFolder?.uri.fsPath,
        });

        const task = new vscode.Task(
            definition,
            workspaceFolder ?? vscode.TaskScope.Workspace,
            this.getTaskName(definition),
            'canopy',
            execution,
            '$canopy'
        );

        task.group = definition.command === 'make' ? vscode.TaskGroup.Build : undefined;

        return task;
    }

    /**
     * Create the default build task.
     */
    private createBuildTask(workspaceFolder: vscode.WorkspaceFolder): vscode.Task {
        const definition: CanopyTaskDefinition = {
            type: CanopyTaskProvider.taskType,
            command: 'make',
        };

        const task = new vscode.Task(
            definition,
            workspaceFolder,
            'Build',
            'canopy',
            new vscode.ShellExecution(this.getCompilerPath(), ['make'], {
                cwd: workspaceFolder.uri.fsPath,
            }),
            '$canopy'
        );

        task.group = vscode.TaskGroup.Build;
        task.presentationOptions = {
            reveal: vscode.TaskRevealKind.Silent,
            panel: vscode.TaskPanelKind.Shared,
            clear: true,
        };

        return task;
    }

    /**
     * Create the optimized build task.
     */
    private createBuildOptimizedTask(workspaceFolder: vscode.WorkspaceFolder): vscode.Task {
        const definition: CanopyTaskDefinition = {
            type: CanopyTaskProvider.taskType,
            command: 'make',
            optimize: true,
        };

        const task = new vscode.Task(
            definition,
            workspaceFolder,
            'Build (Optimized)',
            'canopy',
            new vscode.ShellExecution(this.getCompilerPath(), ['make', '--optimize'], {
                cwd: workspaceFolder.uri.fsPath,
            }),
            '$canopy'
        );

        task.group = vscode.TaskGroup.Build;
        task.presentationOptions = {
            reveal: vscode.TaskRevealKind.Silent,
            panel: vscode.TaskPanelKind.Shared,
            clear: true,
        };

        return task;
    }

    /**
     * Create the type-check only task.
     */
    private createCheckTask(workspaceFolder: vscode.WorkspaceFolder): vscode.Task {
        const definition: CanopyTaskDefinition = {
            type: CanopyTaskProvider.taskType,
            command: 'check',
        };

        const task = new vscode.Task(
            definition,
            workspaceFolder,
            'Check',
            'canopy',
            new vscode.ShellExecution(this.getCompilerPath(), ['check'], {
                cwd: workspaceFolder.uri.fsPath,
            }),
            '$canopy'
        );

        task.presentationOptions = {
            reveal: vscode.TaskRevealKind.Silent,
            panel: vscode.TaskPanelKind.Shared,
            clear: true,
        };

        return task;
    }

    /**
     * Create the REPL task.
     */
    private createReplTask(workspaceFolder: vscode.WorkspaceFolder): vscode.Task {
        const definition: CanopyTaskDefinition = {
            type: CanopyTaskProvider.taskType,
            command: 'repl',
        };

        const task = new vscode.Task(
            definition,
            workspaceFolder,
            'REPL',
            'canopy',
            new vscode.ShellExecution(this.getCompilerPath(), ['repl'], {
                cwd: workspaceFolder.uri.fsPath,
            })
        );

        task.presentationOptions = {
            reveal: vscode.TaskRevealKind.Always,
            panel: vscode.TaskPanelKind.Dedicated,
            focus: true,
        };
        task.isBackground = true;

        return task;
    }

    /**
     * Create the watch mode task.
     */
    private createWatchTask(workspaceFolder: vscode.WorkspaceFolder): vscode.Task {
        const definition: CanopyTaskDefinition = {
            type: CanopyTaskProvider.taskType,
            command: 'watch',
        };

        const task = new vscode.Task(
            definition,
            workspaceFolder,
            'Watch',
            'canopy',
            new vscode.ShellExecution(this.getCompilerPath(), ['watch'], {
                cwd: workspaceFolder.uri.fsPath,
            }),
            '$canopy'
        );

        task.presentationOptions = {
            reveal: vscode.TaskRevealKind.Always,
            panel: vscode.TaskPanelKind.Dedicated,
        };
        task.isBackground = true;

        return task;
    }

    /**
     * Build command arguments from a task definition.
     */
    private buildCommandArgs(definition: CanopyTaskDefinition): string[] {
        const args: string[] = [definition.command];

        if (definition.file) {
            args.push(definition.file);
        }

        if (definition.output) {
            args.push('--output', definition.output);
        }

        if (definition.optimize) {
            args.push('--optimize');
        }

        return args;
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
     * Generate a display name for a task.
     */
    private getTaskName(definition: CanopyTaskDefinition): string {
        const parts: string[] = [];

        switch (definition.command) {
            case 'make':
                parts.push(definition.optimize ? 'Build (Optimized)' : 'Build');
                break;
            case 'check':
                parts.push('Check');
                break;
            case 'repl':
                parts.push('REPL');
                break;
            case 'watch':
                parts.push('Watch');
                break;
            default:
                parts.push(definition.command);
        }

        if (definition.file) {
            parts.push(path.basename(definition.file));
        }

        return parts.join(': ');
    }
}
