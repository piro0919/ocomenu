import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { Link } from "@/i18n/navigation";
import { LanguageSwitch } from "./language-switch";

// お品書きを手本にした頁。Canva の「ベージュ 黒 寿司屋 メニュー 縦」に寄せた。
// 生成りの紙、右端に縦書きの筆文字の題と朱の判子、品名の下に罫、右端に値段、その下に中身を小さく。

const REPO = "https://github.com/piro0919/ocomenu";
const DOWNLOAD = `${REPO}/releases/latest`;
const BREW = "brew install --cask piro0919/tap/ocomenu";

type Course = { name: string; price: string; lines: string[] };
type Step = { title: string; body: string };

type PageProps = {
  params: Promise<{ locale: string }>;
};

/// メニューの見本の1行。"-" は区切り線、"tags" は色のタグの列
type MockRow = string;

/// 見本に並べる中身。Finder の元のメニューは、本人の Mac で出ていたものをそのまま写した（フォルダを右クリック）
const MOCK: Record<"en" | "ja", { before: MockRow[]; after: MockRow[] }> = {
  en: {
    before: [
      "Open in New Tab",
      "-",
      "Move to Trash",
      "-",
      "Get Info",
      "Rename",
      "Compress “Projects”",
      "Duplicate",
      "Make Alias",
      "Quick Look",
      "-",
      "Copy",
      "Share…",
      "-",
      "tags",
      "Customize Folder…",
      "-",
      "Quick Actions ›",
      "-",
      "Folder Actions Setup…",
      "New Terminal Tab at Folder",
      "New Terminal at Folder",
    ],
    after: ["Open in New Tab", "Get Info", "-", "Copy as Pathname", "Open in Terminal"],
  },
  ja: {
    before: [
      "新規タブで開く",
      "-",
      "ゴミ箱に入れる",
      "-",
      "情報を見る",
      "名称変更",
      "“Projects”を圧縮",
      "複製",
      "エイリアスを作成",
      "クイックルック",
      "-",
      "コピー",
      "共有…",
      "-",
      "tags",
      "フォルダをカスタマイズ…",
      "-",
      "クイックアクション ›",
      "-",
      "フォルダアクション設定…",
      "新規ターミナルタブでフォルダに移動",
      "新規ターミナルでフォルダに移動",
    ],
    after: ["新規タブで開く", "情報を見る", "-", "パス名をコピー", "ターミナルで開く"],
  },
};

const TAG_COLORS = ["#ff5f57", "#ff9f0a", "#ffd60a", "#32d74b", "#0a84ff", "#bf5af2", "#8e8e93"];

function MockMenu({ rows }: { rows: MockRow[] }) {
  return (
    <div className="mock-menu w-fit min-w-52 whitespace-nowrap p-1.5 text-[13px] text-neutral-800">
      {rows.map((row, index) => {
        const key = `${row}-${index}`;
        if (row === "-") {
          return <div className="mx-2.5 my-1 h-px bg-neutral-300" key={key} />;
        }
        if (row === "tags") {
          return (
            <div className="flex gap-1.5 px-2.5 py-1.5" key={key}>
              {TAG_COLORS.map((color) => (
                <span className="size-3 rounded-full" key={color} style={{ background: color }} />
              ))}
            </div>
          );
        }
        return (
          <div className="rounded px-2.5 py-[3px]" key={key}>
            {row}
          </div>
        );
      })}
    </div>
  );
}

/// 朱の判子。アイコンと同じく、米粒が3つ並び、真ん中だけが右へ抜けている
function Seal({ label, size = 96 }: { label: string; size?: number }) {
  return (
    <div
      className="seal flex flex-col items-center justify-center gap-1"
      style={{ height: size, width: size }}
    >
      <svg aria-hidden="true" height={size * 0.42} viewBox="0 0 40 34" width={size * 0.5}>
        <rect
          fill="none"
          height="30"
          rx="5"
          stroke="currentColor"
          strokeWidth="2.6"
          width="22"
          x="3"
          y="2"
        />
        <ellipse cx="14" cy="10" fill="currentColor" rx="6.5" ry="3" />
        <ellipse cx="27" cy="17" fill="currentColor" rx="8.5" ry="3" />
        <ellipse cx="14" cy="24" fill="currentColor" rx="6.5" ry="3" />
      </svg>
      <span className="brush text-[13px] leading-none" style={{ fontSize: size * 0.15 }}>
        {label}
      </span>
    </div>
  );
}

function DownloadButton({ children }: { children: ReactNode }) {
  return (
    <a
      className="inline-block border-2 border-[var(--color-ink)] bg-[var(--color-ink)] px-8 py-3.5 font-bold text-[var(--color-rice)] tracking-wider transition hover:bg-transparent hover:text-[var(--color-ink)]"
      href={DOWNLOAD}
    >
      {children}
    </a>
  );
}

/// 品書きの1品。品名の下に罫、右端に値段、その下に中身を小さく
function CourseItem({ course }: { course: Course }) {
  return (
    <li>
      <div className="flex items-baseline justify-between gap-6">
        <h3 className="brush text-2xl sm:text-[28px]">{course.name}</h3>
        <span className="brush shrink-0 text-[var(--color-wood-deep)] text-lg sm:text-xl">
          {course.price}
        </span>
      </div>
      <div className="rule mt-2" />
      <ul className="mt-3 space-y-1 text-[15px] text-[var(--color-ink)]/75 leading-relaxed">
        {course.lines.map((line) => (
          <li key={line}>{line}</li>
        ))}
      </ul>
    </li>
  );
}

export default async function Page({ params }: PageProps) {
  const { locale } = await params;
  setRequestLocale(locale);

  const t = await getTranslations();
  const courses = t.raw("courses.items") as Course[];
  const steps = t.raw("setup.steps") as Step[];
  const mock = MOCK[locale === "ja" ? "ja" : "en"];

  return (
    <>
      <header className="mx-auto flex max-w-6xl items-center justify-between px-4 pt-8 sm:px-6">
        <div className="flex items-center gap-3">
          <Image alt="" height={40} src="/icon.png" width={40} />
          <span className="font-bold text-lg tracking-wide">Ocomenu</span>
        </div>
        <LanguageSwitch />
      </header>

      <main className="mx-auto max-w-6xl px-4 pt-10 pb-20 sm:px-6">
        <div className="sheet px-5 py-8 sm:px-12 sm:py-14">
          {/* 広い画面では題と判子を右端に縦に置く。狭い画面では上に回し、本文を全幅で流す */}
          <div className="flex flex-col-reverse gap-10 lg:flex-row lg:gap-14">
            {/* 左: 品書き。右: 縦書きの題と判子 */}
            <div className="min-w-0 flex-1">
              {/* 口上 */}
              <p className="text-[var(--color-wood-deep)] text-sm tracking-[0.3em]">
                {t("hero.kicker")}
              </p>
              <h1 className="mt-4 font-extrabold text-3xl leading-snug sm:text-5xl sm:leading-tight">
                {t("hero.title")}
              </h1>
              <p className="mt-6 max-w-2xl text-[var(--color-ink)]/80 text-base leading-loose sm:text-lg">
                {t("hero.lead")}
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-4">
                <DownloadButton>{t("hero.download")}</DownloadButton>
                <div className="text-sm">
                  <span className="text-[var(--color-ink)]/60">{t("hero.brew")}</span>
                  <code className="mt-1 block font-mono text-[13px]">{BREW}</code>
                </div>
              </div>
              <p className="mt-4 text-[var(--color-ink)]/55 text-sm">{t("hero.requirement")}</p>

              {/* 元のメニューと、組んだメニュー */}
              <div className="mt-14 flex flex-wrap items-start gap-x-10 gap-y-8">
                <figure>
                  <figcaption className="mb-3 text-[var(--color-ink)]/60 text-sm">
                    {t("compare.before")}
                  </figcaption>
                  <MockMenu rows={mock.before} />
                </figure>
                <div
                  aria-hidden="true"
                  className="brush self-center text-4xl text-[var(--color-wood-deep)]"
                >
                  →
                </div>
                <figure>
                  <figcaption className="mb-3 text-[var(--color-ink)]/60 text-sm">
                    {t("compare.after")}
                  </figcaption>
                  <MockMenu rows={mock.after} />
                </figure>
              </div>

              {/* 品書き */}
              <section className="mt-20">
                <h2 className="brush text-3xl">{t("courses.title")}</h2>
                <ul className="mt-8 space-y-12">
                  {courses.map((course) => (
                    <CourseItem course={course} key={course.name} />
                  ))}
                </ul>
                <figure className="mt-14">
                  <Image
                    alt=""
                    className="w-full max-w-3xl rounded-xl shadow-[0_18px_40px_rgb(31_42_90/0.25)]"
                    height={1108}
                    src={locale === "ja" ? "/settings-ja.png" : "/settings-en.png"}
                    width={1584}
                  />
                </figure>
              </section>

              {/* ご注文の前に */}
              <section className="mt-20">
                <h2 className="brush text-3xl">{t("setup.title")}</h2>
                <ol className="mt-8 grid gap-8 sm:grid-cols-2">
                  {steps.map((step, index) => (
                    <li className="flex gap-4" key={step.title}>
                      <span className="brush text-3xl text-[var(--color-wood-deep)] leading-none">
                        {["一", "二", "三", "四"][index]}
                      </span>
                      <div>
                        <h3 className="font-bold">{step.title}</h3>
                        <p className="mt-2 text-[15px] text-[var(--color-ink)]/75 leading-relaxed">
                          {step.body}
                        </p>
                      </div>
                    </li>
                  ))}
                </ol>
                <p className="mt-8 text-[var(--color-ink)]/60 text-sm leading-relaxed">
                  {t("setup.note")}
                </p>
              </section>

              {/* お代 */}
              <section className="mt-20">
                <div className="flex items-baseline justify-between gap-6">
                  <h2 className="brush text-3xl">{t("price.title")}</h2>
                  <span className="brush text-3xl text-[var(--color-wood-deep)]">
                    {t("price.amount")}
                  </span>
                </div>
                <div className="rule mt-2" />
                <p className="mt-4 text-[15px] text-[var(--color-ink)]/75 leading-relaxed">
                  {t("price.body")}
                </p>
                <div className="mt-8">
                  <DownloadButton>{t("price.cta")}</DownloadButton>
                </div>
              </section>
            </div>

            {/* 縦書きの題と判子。狭い画面では小さくして残す */}
            <div className="flex shrink-0 items-start justify-end gap-6 lg:flex-col lg:items-center lg:justify-start lg:gap-8">
              <p
                aria-hidden="true"
                className="brush tategaki text-4xl leading-none sm:text-6xl lg:text-8xl"
              >
                おこめにゅぅ
              </p>
              <Seal label={t("seal")} />
            </div>
          </div>
        </div>
      </main>

      <footer className="flex justify-center gap-6 px-6 pb-12 text-sm">
        <a className="opacity-60 hover:opacity-100" href={REPO}>
          {t("footer.source")}
        </a>
        <a className="opacity-60 hover:opacity-100" href={`${REPO}/releases`}>
          {t("footer.releases")}
        </a>
        <Link className="opacity-60 hover:opacity-100" href="/privacy">
          {t("footer.privacy")}
        </Link>
        <a className="opacity-60 hover:opacity-100" href="https://buymeacoffee.com/piro0919">
          Buy Me a Coffee
        </a>
      </footer>
    </>
  );
}
