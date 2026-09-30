import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { routing } from "@/i18n/routing";

export const alt = "Ocomenu";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/* ビルド時に焼く。動的なままだと public/ が関数側に含まれず、
   本番で icon.png を読めずに 500 になる */
export function generateStaticParams(): { locale: string }[] {
  return routing.locales.map((locale) => ({ locale }));
}

/* 出るのは kk-web の一覧で176px、X のカードで500px 前後。
   その大きさで残るのはアイコンと名前と1行だけ。色はアイコンから取る。
   地はアイコンの地と同じ生成りにすると輪郭が溶けるので、板の藍色を地にする */
const INK = "#1f2a5a";
const PAPER = "#f6ebd2";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";
  /* 書体はサイトの題と同じ Yuji Syuku。使う文字だけに絞ったものを同梱している。
     文言を変えたら assets/README.md の手順で作り直す */
  const [icon, font] = await Promise.all([
    readFile(join(process.cwd(), "public/icon.png")),
    readFile(join(process.cwd(), "assets/YujiSyuku-subset.ttf")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        background: INK,
        display: "flex",
        /* kk-web の一覧は 176×99 に縮めて左右を切る。1200×630 との比の差で、左右が3%ずつ欠ける。
           日本語の副題の末尾が欠けたので、中身を中央に寄せて左右に余白を取る */
        gap: 48,
        paddingLeft: 90,
        paddingRight: 90,
        height: "100%",
        justifyContent: "center",
        width: "100%",
      }}
    >
      <div style={{ borderRadius: 60, display: "flex", overflow: "hidden" }}>
        {/* biome-ignore lint/performance/noImgElement: next/image is not available in ImageResponse */}
        <img alt="" height={240} src={iconSrc} width={240} />
      </div>
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ color: PAPER, fontSize: 132, lineHeight: 1 }}>Ocomenu</div>
        <div style={{ color: PAPER, display: "flex", fontSize: 34, marginTop: 22, opacity: 0.85 }}>
          {isJa ? "Finder の右クリックを、自分のお品書きに" : "Finder's right-click menu, your way"}
        </div>
      </div>
    </div>,
    {
      ...size,
      fonts: [{ data: font, name: "Yuji Syuku", style: "normal", weight: 400 }],
    },
  );
}
