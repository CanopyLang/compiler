import LZString from 'lz-string';
import type { PlaygroundFile } from '../types';

interface ShareData {
  files: PlaygroundFile[];
  activeFileIndex: number;
}

export function encodeShareUrl(files: PlaygroundFile[], activeFileIndex: number): string {
  const data: ShareData = { files, activeFileIndex };
  const json = JSON.stringify(data);
  const compressed = LZString.compressToEncodedURIComponent(json);
  return `${window.location.origin}${window.location.pathname}#code=${compressed}`;
}

export function decodeShareUrl(): ShareData | null {
  const hash = window.location.hash;
  if (!hash.startsWith('#code=')) {
    return null;
  }

  try {
    const compressed = hash.slice(6);
    const json = LZString.decompressFromEncodedURIComponent(compressed);
    if (!json) {
      return null;
    }
    return JSON.parse(json) as ShareData;
  } catch {
    return null;
  }
}

export async function copyToClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-9999px';
    document.body.appendChild(textArea);
    textArea.select();
    try {
      document.execCommand('copy');
      return true;
    } catch {
      return false;
    } finally {
      document.body.removeChild(textArea);
    }
  }
}

export async function downloadAsZip(files: PlaygroundFile[]): Promise<void> {
  const createZipManually = async () => {
    const content = files.map(f => `=== ${f.name} ===\n${f.content}`).join('\n\n');
    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'canopy-project.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  await createZipManually();
}
