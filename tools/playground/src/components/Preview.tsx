import { useMemo, useRef, useEffect, useState } from 'react';

interface PreviewProps {
  compiledOutput: string;
  isCompiling: boolean;
}

const PREVIEW_HTML_TEMPLATE = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      font-family: system-ui, -apple-system, sans-serif;
      line-height: 1.5;
      color: #1e293b;
    }
    #app {
      min-height: 100vh;
    }
  </style>
</head>
<body>
  <div id="app"></div>
  <script>
    // Runtime support for Canopy applications
    var Canopy = {
      Html: {
        div: function(attrs, children) {
          var el = document.createElement('div');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        h1: function(attrs, children) {
          var el = document.createElement('h1');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        h2: function(attrs, children) {
          var el = document.createElement('h2');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        p: function(attrs, children) {
          var el = document.createElement('p');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        span: function(attrs, children) {
          var el = document.createElement('span');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        button: function(attrs, children) {
          var el = document.createElement('button');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        input: function(attrs) {
          var el = document.createElement('input');
          applyAttrs(el, attrs);
          return el;
        },
        ul: function(attrs, children) {
          var el = document.createElement('ul');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        li: function(attrs, children) {
          var el = document.createElement('li');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        pre: function(attrs, children) {
          var el = document.createElement('pre');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        code: function(attrs, children) {
          var el = document.createElement('code');
          applyAttrs(el, attrs);
          appendChildren(el, children);
          return el;
        },
        text: function(str) {
          return document.createTextNode(String(str));
        }
      }
    };

    function applyAttrs(el, attrs) {
      if (!attrs) return;
      attrs.forEach(function(attr) {
        if (attr.type === 'style') {
          el.style[attr.name] = attr.value;
        } else if (attr.type === 'onClick') {
          el.addEventListener('click', function() {
            if (window._canopyApp && window._canopyApp.update) {
              window._canopyApp.update(attr.msg);
            }
          });
        } else if (attr.name) {
          el.setAttribute(attr.name, attr.value);
        }
      });
    }

    function appendChildren(el, children) {
      if (!children) return;
      children.forEach(function(child) {
        if (typeof child === 'string') {
          el.appendChild(document.createTextNode(child));
        } else if (child instanceof Node) {
          el.appendChild(child);
        }
      });
    }

    // Make runtime globally available
    window.Canopy = Canopy;
  </script>
  <script>
    // User compiled code will be inserted here
    {{COMPILED_CODE}}
  </script>
  <script>
    // Initialize the application
    document.addEventListener('DOMContentLoaded', function() {
      var app = document.getElementById('app');
      try {
        // Look for a main function in any defined module
        var mainFound = false;
        for (var key in window) {
          if (window[key] && typeof window[key].main === 'function') {
            var result = window[key].main;
            if (result instanceof Node) {
              app.appendChild(result);
              mainFound = true;
              break;
            }
          }
        }
        if (!mainFound) {
          app.innerHTML = '<div style="padding: 2rem; text-align: center; color: #64748b;">No output to preview. Define a <code>main</code> function.</div>';
        }
      } catch (e) {
        app.innerHTML = '<div style="padding: 1rem; background: #fee2e2; border: 1px solid #fecaca; border-radius: 4px; color: #991b1b;">' +
          '<strong>Runtime Error:</strong><br>' + e.message + '</div>';
        console.error('Runtime error:', e);
      }
    });
  </script>
</body>
</html>
`;

export function Preview({ compiledOutput, isCompiling }: PreviewProps): JSX.Element {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [hasError, setHasError] = useState(false);

  const previewHtml = useMemo(() => {
    if (!compiledOutput) {
      return PREVIEW_HTML_TEMPLATE.replace('{{COMPILED_CODE}}', '// No compiled code');
    }
    return PREVIEW_HTML_TEMPLATE.replace('{{COMPILED_CODE}}', compiledOutput);
  }, [compiledOutput]);

  useEffect(() => {
    if (!iframeRef.current) return;

    try {
      const blob = new Blob([previewHtml], { type: 'text/html' });
      const url = URL.createObjectURL(blob);

      iframeRef.current.src = url;
      setHasError(false);

      return () => {
        URL.revokeObjectURL(url);
      };
    } catch (error) {
      setHasError(true);
      console.error('Preview error:', error);
    }
  }, [previewHtml]);

  if (isCompiling) {
    return (
      <div className="preview-container" style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#ffffff',
      }}>
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: '0.5rem',
          color: '#64748b',
        }}>
          <div className="loading-spinner" />
          <span>Compiling...</span>
        </div>
      </div>
    );
  }

  if (hasError) {
    return (
      <div className="preview-container" style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '2rem',
        backgroundColor: '#ffffff',
      }}>
        <div style={{
          textAlign: 'center',
          color: '#991b1b',
        }}>
          <p>Failed to render preview</p>
          <p style={{ fontSize: '0.875rem', color: '#64748b', marginTop: '0.5rem' }}>
            Check the console for errors
          </p>
        </div>
      </div>
    );
  }

  return (
    <iframe
      ref={iframeRef}
      className="preview-iframe"
      title="Canopy Preview"
      sandbox="allow-scripts allow-same-origin"
    />
  );
}
