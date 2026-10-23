import type { PluralText } from './landing';

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const LINE_SEPARATOR = String.fromCharCode(0x2028);
const PARAGRAPH_SEPARATOR = String.fromCharCode(0x2029);
const uncounted = new Set([
  '\t',
  '\n',
  '\r',
  '\r\n',
  '\v',
  '\f',
  '\x85',
  LINE_SEPARATOR,
  PARAGRAPH_SEPARATOR,
]);

export function countCharacters(text: string): number {
  let count = 0;
  for (const { segment } of segmenter.segment(text)) {
    if (!uncounted.has(segment)) {
      count++;
    }
  }
  return count;
}

export function pluralize(text: PluralText, count: number, locale: string): string {
  const form = text[new Intl.PluralRules(locale).select(count)] ?? text.other;
  return form.replace('{count}', count.toLocaleString(locale));
}
