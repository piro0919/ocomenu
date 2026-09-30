"use client";

import { useLocale, useTranslations } from "next-intl";
import { Link, usePathname } from "@/i18n/navigation";

/// 言語の切り替え。既定が英語なので、日本語話者が辿り着ける入口が要る
export function LanguageSwitch() {
  const locale = useLocale();
  const t = useTranslations("language");
  const pathname = usePathname();

  return (
    <div className="flex items-center gap-3 text-sm">
      {(["en", "ja"] as const).map((target, index) => (
        <span className="flex items-center gap-3" key={target}>
          {index > 0 && (
            <span aria-hidden="true" className="opacity-30">
              /
            </span>
          )}
          <Link
            className={
              locale === target
                ? "font-bold underline decoration-1 underline-offset-4"
                : "opacity-55 transition hover:opacity-100"
            }
            href={pathname}
            locale={target}
          >
            {t(target)}
          </Link>
        </span>
      ))}
    </div>
  );
}
