#!/usr/bin/env node

/**
 * Canopy Time-Travel Debugger Server
 *
 * WebSocket server that bridges the Canopy application with debugger UIs
 * (browser extension, VS Code panel, etc.)
 */

const WebSocket = require('ws');
const http = require('http');
const url = require('url');

const DEFAULT_PORT = 8765;
const DEFAULT_HOST = 'localhost';

/**
 * Debugger server state
 */
class DebuggerServer {
  constructor(options = {}) {
    this.port = options.port || DEFAULT_PORT;
    this.host = options.host || DEFAULT_HOST;
    this.clients = new Map();
    this.sessions = new Map();
    this.currentSession = null;
    this.history = [];
    this.wss = null;
    this.httpServer = null;
  }

  /**
   * Start the debugger server
   */
  start() {
    return new Promise((resolve, reject) => {
      this.httpServer = http.createServer(this.handleHttpRequest.bind(this));
      this.wss = new WebSocket.Server({ server: this.httpServer });

      this.wss.on('connection', this.handleConnection.bind(this));
      this.wss.on('error', (error) => {
        console.error('[Debugger Server] WebSocket error:', error);
      });

      this.httpServer.listen(this.port, this.host, () => {
        console.log(`[Debugger Server] Running at ws://${this.host}:${this.port}`);
        resolve();
      });

      this.httpServer.on('error', reject);
    });
  }

  /**
   * Stop the debugger server
   */
  stop() {
    return new Promise((resolve) => {
      this.clients.forEach((client) => {
        if (client.ws.readyState === WebSocket.OPEN) {
          client.ws.close();
        }
      });

      if (this.wss) {
        this.wss.close();
      }

      if (this.httpServer) {
        this.httpServer.close(resolve);
      } else {
        resolve();
      }
    });
  }

  /**
   * Handle HTTP requests (for REST API endpoints)
   */
  handleHttpRequest(req, res) {
    const parsedUrl = url.parse(req.url, true);

    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.writeHead(200);
      res.end();
      return;
    }

    switch (parsedUrl.pathname) {
      case '/':
        this.handleRoot(req, res);
        break;

      case '/api/status':
        this.handleStatus(req, res);
        break;

      case '/api/history':
        this.handleHistoryRequest(req, res);
        break;

      case '/api/sessions':
        this.handleSessionsRequest(req, res);
        break;

      case '/api/export':
        this.handleExportRequest(req, res);
        break;

      case '/api/import':
        this.handleImportRequest(req, res);
        break;

      default:
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not found' }));
    }
  }

  /**
   * Handle WebSocket connections
   */
  handleConnection(ws, req) {
    const clientId = this.generateClientId();
    const clientType = this.parseClientType(req);

    const client = {
      id: clientId,
      type: clientType,
      ws: ws,
      connectedAt: Date.now()
    };

    this.clients.set(clientId, client);
    console.log(`[Debugger Server] Client connected: ${clientId} (${clientType})`);

    ws.on('message', (data) => {
      this.handleMessage(client, data);
    });

    ws.on('close', () => {
      this.clients.delete(clientId);
      console.log(`[Debugger Server] Client disconnected: ${clientId}`);
    });

    ws.on('error', (error) => {
      console.error(`[Debugger Server] Client error (${clientId}):`, error);
    });

    // Send welcome message
    this.sendToClient(client, {
      type: 'welcome',
      clientId: clientId,
      serverVersion: '1.0.0',
      historyLength: this.history.length
    });

    // Send current state if there is one
    if (this.history.length > 0) {
      this.sendToClient(client, {
        type: 'sync',
        history: this.history
      });
    }
  }

  /**
   * Handle incoming WebSocket messages
   */
  handleMessage(client, data) {
    try {
      const message = JSON.parse(data);
      this.processMessage(client, message);
    } catch (e) {
      console.error('[Debugger Server] Failed to parse message:', e);
    }
  }

  /**
   * Process a parsed message
   */
  processMessage(client, message) {
    switch (message.type) {
      case 'handshake':
        this.handleHandshake(client, message);
        break;

      case 'entry':
        this.handleEntry(client, message);
        break;

      case 'command':
        this.handleCommand(client, message);
        break;

      case 'jumpTo':
        this.broadcastToOthers(client, message);
        break;

      case 'stepForward':
      case 'stepBackward':
        this.broadcastToOthers(client, message);
        break;

      case 'sessionExported':
        this.handleSessionExported(client, message);
        break;

      case 'getHistory':
        this.sendToClient(client, {
          type: 'history',
          history: this.history
        });
        break;

      case 'clearHistory':
        this.history = [];
        this.broadcast({ type: 'historyCleared' });
        break;

      case 'ping':
        this.sendToClient(client, {
          type: 'pong',
          timestamp: Date.now()
        });
        break;

      default:
        // Forward unknown messages to other clients
        this.broadcastToOthers(client, message);
    }
  }

  /**
   * Handle handshake from a client
   */
  handleHandshake(client, message) {
    client.version = message.version;
    client.capabilities = message.capabilities || [];

    this.sendToClient(client, {
      type: 'handshakeAck',
      serverVersion: '1.0.0'
    });
  }

  /**
   * Handle a new entry from the application
   */
  handleEntry(client, message) {
    const entry = {
      ...message.entry,
      receivedAt: Date.now(),
      clientId: client.id
    };

    this.history.push(entry);

    // Broadcast to debugger UIs
    this.broadcastToType('debugger', {
      type: 'entry',
      entry: entry
    });

    this.broadcastToType('extension', {
      type: 'entry',
      entry: entry
    });
  }

  /**
   * Handle commands from debugger UIs
   */
  handleCommand(client, message) {
    // Forward commands to the application
    this.broadcastToType('application', {
      type: 'command',
      command: message.command,
      payload: message.payload
    });
  }

  /**
   * Handle exported session
   */
  handleSessionExported(client, message) {
    const sessionId = this.generateSessionId();
    this.sessions.set(sessionId, {
      id: sessionId,
      data: message.session,
      createdAt: Date.now(),
      clientId: client.id
    });

    this.sendToClient(client, {
      type: 'sessionSaved',
      sessionId: sessionId
    });
  }

  /**
   * Send a message to a specific client
   */
  sendToClient(client, message) {
    if (client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify(message));
    }
  }

  /**
   * Broadcast a message to all clients
   */
  broadcast(message) {
    const payload = JSON.stringify(message);
    this.clients.forEach((client) => {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    });
  }

  /**
   * Broadcast to all clients except the sender
   */
  broadcastToOthers(sender, message) {
    const payload = JSON.stringify(message);
    this.clients.forEach((client) => {
      if (client.id !== sender.id && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    });
  }

  /**
   * Broadcast to clients of a specific type
   */
  broadcastToType(type, message) {
    const payload = JSON.stringify(message);
    this.clients.forEach((client) => {
      if (client.type === type && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    });
  }

  /**
   * Parse client type from request
   */
  parseClientType(req) {
    const parsedUrl = url.parse(req.url, true);
    return parsedUrl.query.type || 'application';
  }

  /**
   * Generate a unique client ID
   */
  generateClientId() {
    return 'client_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  /**
   * Generate a unique session ID
   */
  generateSessionId() {
    return 'session_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  // HTTP API Handlers

  handleRoot(req, res) {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
      <!DOCTYPE html>
      <html>
        <head><title>Canopy Debugger Server</title></head>
        <body>
          <h1>Canopy Time-Travel Debugger Server</h1>
          <p>WebSocket endpoint: ws://${this.host}:${this.port}</p>
          <p>Connected clients: ${this.clients.size}</p>
          <p>History entries: ${this.history.length}</p>
          <h2>API Endpoints</h2>
          <ul>
            <li>GET /api/status - Server status</li>
            <li>GET /api/history - Current history</li>
            <li>GET /api/sessions - Saved sessions</li>
            <li>POST /api/export - Export current session</li>
            <li>POST /api/import - Import a session</li>
          </ul>
        </body>
      </html>
    `);
  }

  handleStatus(req, res) {
    const status = {
      running: true,
      port: this.port,
      host: this.host,
      clients: this.clients.size,
      historyLength: this.history.length,
      sessions: this.sessions.size,
      uptime: process.uptime()
    };

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(status));
  }

  handleHistoryRequest(req, res) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ history: this.history }));
  }

  handleSessionsRequest(req, res) {
    const sessions = Array.from(this.sessions.values()).map(s => ({
      id: s.id,
      createdAt: s.createdAt
    }));

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ sessions: sessions }));
  }

  handleExportRequest(req, res) {
    const session = {
      version: '1.0.0',
      timestamp: Date.now(),
      history: this.history
    };

    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Content-Disposition': 'attachment; filename="canopy-debug-session.json"'
    });
    res.end(JSON.stringify(session, null, 2));
  }

  handleImportRequest(req, res) {
    if (req.method !== 'POST') {
      res.writeHead(405, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Method not allowed' }));
      return;
    }

    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const session = JSON.parse(body);
        this.history = session.history || [];

        this.broadcast({
          type: 'sessionImported',
          historyLength: this.history.length
        });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, historyLength: this.history.length }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid session data' }));
      }
    });
  }
}

// CLI entry point
if (require.main === module) {
  const args = process.argv.slice(2);
  const options = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--port' || args[i] === '-p') {
      options.port = parseInt(args[++i], 10);
    } else if (args[i] === '--host' || args[i] === '-h') {
      options.host = args[++i];
    }
  }

  const server = new DebuggerServer(options);

  server.start().catch((error) => {
    console.error('Failed to start debugger server:', error);
    process.exit(1);
  });

  process.on('SIGINT', () => {
    console.log('\nShutting down...');
    server.stop().then(() => process.exit(0));
  });
}

module.exports = { DebuggerServer };
