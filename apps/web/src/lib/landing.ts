import type { ImageMetadata } from 'astro';
import figEn01 from '@/assets/landing/fig-en-01.webp';
import figEn02 from '@/assets/landing/fig-en-02.webp';
import figEn03 from '@/assets/landing/fig-en-03.webp';
import figEn04 from '@/assets/landing/fig-en-04.webp';
import figJa01 from '@/assets/landing/fig-ja-01.webp';
import figJa02 from '@/assets/landing/fig-ja-02.webp';
import figJa03 from '@/assets/landing/fig-ja-03.webp';
import figJa04 from '@/assets/landing/fig-ja-04.webp';
import type { Locale } from './site';

export interface LandingFeature {
  image: ImageMetadata;
  alt: string;
  title: string;
  body: string;
  link?: { slug: string; label: string };
}

export type PluralText = Partial<Record<Intl.LDMLPluralRule, string>> & { other: string };

export interface LandingDemo {
  label: string;
  text: readonly (string | { text: string; lang: Locale })[];
  statusBar: {
    characters: PluralText;
    selected: PluralText;
    withSelection: string;
  };
}

export interface LandingContent {
  tagline: string;
  demo: LandingDemo;
  download: {
    label: string;
    requirement: string;
    pricing: string;
  };
  features: readonly LandingFeature[];
}

export const landingContent: Record<Locale, LandingContent> = {
  ja: {
    tagline: '文章を書きたくなるテキストエディタ',
    demo: {
      label: 'Plainsongのウィンドウ',
      text: [
        '文章を書きたくなるテキストエディタ',
        { text: 'A text editor that makes you want to write', lang: 'en' },
        '',
        'Plainsongは、プレーンテキストを編集できるmacOS専用のテキストエディタです。',
        '文章を書くこと、読むことに特化し、軽量に動作します。文字や行間の大きさ、余白の空け方など、執筆スタイルにあわせてカスタマイズできます。メニューバーに常駐するので、「書こう」と思ったときにすぐに書き始められます。',
        'オープンソースのソフトウェアで、無料で使えます。',
      ],
      statusBar: {
        characters: { other: '{count}文字' },
        selected: { other: '{count}文字を選択中' },
        withSelection: '{total}（{selected}）',
      },
    },
    download: {
      label: 'Mac App Storeでダウンロード',
      requirement: 'macOS 26以上',
      pricing: '無料',
    },
    features: [
      {
        image: figJa01,
        alt: '設定ウィンドウの「一般」。文字サイズ、行間、フォントと、行番号の表示などのオプションが並んでいる',
        title: '書きやすくて、読みやすい',
        body: 'ファイルの名前を決めなくても、起動するだけで、すぐに書き始められます。文字サイズ、行間、段落の間の余白、字下げなど、あなたの執筆スタイルにあわせて細かくカスタマイズできます。',
      },
      {
        image: figJa02,
        alt: 'Plainsongのウィンドウ。行番号の横にアプリの紹介文が書かれている',
        title: '自動で保存',
        body: 'ファイルに保存していなくても、Plainsongがバックアップ。ウィンドウを閉じても復元できます。また、テキストファイルに保存すれば、編集するたびに自動で保存する設定もできます。',
      },
      {
        image: figJa03,
        alt: 'ダークモードで表示した設定ウィンドウの「テーマ」。Catppuccin、GitHub、Icebergなどのテーマが並んでいる',
        title: 'ダークモード対応',
        body: 'macOSのダークモードに対応しているほか、Ghosttyのテーマファイルと互換性を持つので、ターミナルなど他のアプリケーションと同じ配色に揃えることができます。',
      },
      {
        image: figJa04,
        alt: '設定ウィンドウの「機能拡張」。ツールバーのコピー、保存、共有、削除と、ステータスバーの文字数を、それぞれオンとオフで切り替えられる',
        title: '選べる機能拡張',
        body: '文章に含まれる文字や単語の数を数えたり、ウィンドウの右上にクリップボードへコピーするボタンを置いたり。あなたに必要な機能だけ選んで追加できる仕組みだから、執筆に集中できます。',
      },
    ],
  },
  en: {
    tagline: 'A text editor that makes you want to write',
    demo: {
      label: 'Plainsong window',
      text: [
        'A text editor that makes you want to write',
        '',
        'Plainsong is a plain text editor made just for the Mac.',
        'Focused on writing and reading, it stays light. Customize the text size, line spacing, paragraph spacing, and more to suit the way you write. It lives in your menu bar, so you can start writing the moment you want to.',
        'Plainsong is free and open source.',
      ],
      statusBar: {
        characters: { one: '{count} character', other: '{count} characters' },
        selected: { other: '{count} selected' },
        withSelection: '{total} ({selected})',
      },
    },
    download: {
      label: 'Download on the Mac App Store',
      requirement: 'Requires macOS 26 or later',
      pricing: 'Free',
    },
    features: [
      {
        image: figEn01,
        alt: 'The General pane of the settings window, showing text size, line spacing, font, and options such as Show Line Numbers',
        title: 'Easy to write, easy to read',
        body: 'No need to name a file first. Just open the app and start writing. Fine-tune the text size, line spacing, paragraph spacing, indentation, and more to suit the way you write.',
      },
      {
        image: figEn02,
        alt: 'A Plainsong window with an introduction to the app written next to line numbers',
        title: 'Autosave',
        body: 'Even before you save to a file, Plainsong keeps a backup, so you can restore your writing after closing the window. Once you save it as a text file, you can also turn on autosave to save your changes every time you edit.',
      },
      {
        image: figEn03,
        alt: 'The Theme pane of the settings window in Dark Mode, listing themes such as Catppuccin, GitHub, and Iceberg',
        title: 'Dark Mode support',
        body: 'Plainsong supports Dark Mode on macOS and is compatible with Ghostty theme files, so you can match the colors of your terminal and other apps.',
      },
      {
        image: figEn04,
        alt: 'The Extensions pane of the settings window, where Copy, Save, Share, and Delete in the toolbar and Character Count in the status bar can each be turned on or off',
        title: 'Extensions you choose',
        body: 'Count the characters and words in your writing, or add a button to the top-right corner of the window that copies your text to the clipboard. Choose and add only the features you need, so you can stay focused on writing.',
      },
    ],
  },
};
