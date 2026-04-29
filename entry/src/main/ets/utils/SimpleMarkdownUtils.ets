export interface MarkdownBlock {
  kind: 'heading' | 'bullet' | 'ordered' | 'paragraph' | 'divider';
  text: string;
  prefix: string;
  level: number;
  indent: number;
}

interface HeadingParseResult {
  level: number;
  text: string;
}

function cleanInlineMarkdown(text: string): string {
  return text
    .split('**').join('')
    .split('__').join('')
    .split('`').join('')
    .trim();
}

function normalizeMarkdownSource(content: string): string {
  return content
    .split('\r\n').join('\n')
    .split('\r').join('\n')
    .replace(/([^\n])(#{1,6})([^#\s])/g, '$1\n\n$2 $3')
    .replace(/^(#{1,6})([^#\s])/gm, '$1 $2')
    .replace(/(#{1,6}\s+[^\n]+?)(\d+[.\u3001])/g, '$1\n$2')
    .replace(/([\u3002\uff1b;])(\d+[.\u3001])/g, '$1\n$2')
    .replace(/^(\s*\d+[.\u3001])([^\s])/gm, '$1 $2');
}

function readHeading(line: string): HeadingParseResult | null {
  if (!line.startsWith('#')) {
    return null;
  }

  let level = 0;
  while (level < line.length && level < 6 && line.charAt(level) === '#') {
    level++;
  }

  const text = cleanInlineMarkdown(line.substring(level));
  if (text.length === 0) {
    return null;
  }

  return {
    level: level,
    text: text
  };
}

function orderedPrefixEnd(line: string): number {
  let index = 0;
  while (index < line.length) {
    const code = line.charCodeAt(index);
    if (code < 48 || code > 57) {
      break;
    }
    index++;
  }

  if (index === 0 || index >= line.length) {
    return -1;
  }

  const separatorCode = line.charCodeAt(index);
  if (separatorCode !== 46 && separatorCode !== 12289) {
    return -1;
  }
  return index + 1;
}

function normalizeOrderedPrefix(prefix: string): string {
  let digits = '';
  for (let index = 0; index < prefix.length; index++) {
    const code = prefix.charCodeAt(index);
    if (code >= 48 && code <= 57) {
      digits += prefix.charAt(index);
    }
  }
  return digits.length > 0 ? `${digits}.` : prefix;
}

function leadingSpaceCount(rawLine: string): number {
  let count = 0;
  while (count < rawLine.length) {
    const char = rawLine.charAt(count);
    if (char === ' ') {
      count++;
      continue;
    }
    if (char === '\t') {
      count += 4;
      continue;
    }
    break;
  }
  return count;
}

function markdownIndent(rawLine: string): number {
  return Math.min(3, Math.floor(leadingSpaceCount(rawLine) / 2));
}

function isBulletLine(line: string): boolean {
  if (line.startsWith('- ') || line.startsWith('* ')) {
    return true;
  }
  return line.length > 1 && line.charCodeAt(0) === 8226 && line.charAt(1) === ' ';
}

function mergeParagraphBlock(blocks: MarkdownBlock[], text: string): void {
  const cleanText = cleanInlineMarkdown(text);
  if (cleanText.length === 0) {
    return;
  }

  const lastIndex = blocks.length - 1;
  if (lastIndex >= 0 && blocks[lastIndex].kind === 'paragraph') {
    blocks[lastIndex].text = `${blocks[lastIndex].text}\n${cleanText}`;
    return;
  }

  blocks.push({
    kind: 'paragraph',
    text: cleanText,
    prefix: '',
    level: 0,
    indent: 0
  });
}

export function parseSimpleMarkdownBlocks(content: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const normalized = normalizeMarkdownSource(content);

  normalized.split('\n').forEach((rawLine: string) => {
    const line = rawLine.trim();
    const indent = markdownIndent(rawLine);
    if (line.length === 0) {
      return;
    }
    if (/^#{1,6}$/.test(line)) {
      return;
    }

    if (line === '---' || line === '***' || line === '___') {
      blocks.push({
        kind: 'divider',
        text: '',
        prefix: '',
        level: 0,
        indent: 0
      });
      return;
    }

    const heading = readHeading(line);
    if (heading !== null) {
      blocks.push({
        kind: 'heading',
        text: heading.text,
        prefix: '',
        level: heading.level,
        indent: 0
      });
      return;
    }

    if (isBulletLine(line)) {
      blocks.push({
        kind: 'bullet',
        text: cleanInlineMarkdown(line.substring(2)),
        prefix: '',
        level: 0,
        indent: indent
      });
      return;
    }

    const orderedEnd = orderedPrefixEnd(line);
    if (orderedEnd > 0) {
      blocks.push({
        kind: 'ordered',
        text: cleanInlineMarkdown(line.substring(orderedEnd)),
        prefix: normalizeOrderedPrefix(line.substring(0, orderedEnd)),
        level: 0,
        indent: indent
      });
      return;
    }

    mergeParagraphBlock(blocks, line);
  });

  if (blocks.length === 0 && content.trim().length > 0) {
    blocks.push({
      kind: 'paragraph',
      text: cleanInlineMarkdown(content),
      prefix: '',
      level: 0,
      indent: 0
    });
  }

  return blocks;
}
