import type { FC } from "react";
import { Hero, type Pose } from "./Hero";

const poses: { pose: Pose; title: string; note: string; look: number }[] = [
  { pose: "proud", title: "01 · Всё под контролем", note: "гордость перед маленькой катастрофой", look: 0 },
  { pose: "caught", title: "02 · Это не я", note: "взгляд выдаёт больше, чем жест", look: -0.7 },
  { pose: "working", title: "03 · Дай я помогу", note: "действие начинается с переноса веса", look: 0.85 },
  { pose: "surprised", title: "04 · Подожди!", note: "реакция целым телом", look: 0.9 },
  { pose: "soft", title: "05 · Спасибо, хвост", note: "помощь иногда действительно нужна", look: 0.8 },
  { pose: "deadpan", title: "06 · Ну конечно", note: "пауза завершает шутку", look: 0.9 },
];

export const CharacterSheet: FC = () => (
  <svg width="100%" height="100%" viewBox="0 0 2400 1600" style={{ fontFamily: "DejaVu Sans, sans-serif" }}>
    <rect width="2400" height="1600" fill="#f5efdf" />
    <rect x="0" y="0" width="2400" height="13" fill="#61435f" />
    <text x="100" y="107" fontSize="26" letterSpacing="5" fill="#88766a">CARTOON REELS / РАБОЧИЙ ДИЗАЙН 01</text>
    <text x="96" y="191" fontSize="70" fontWeight="bold" fill="#243f46">Хвост спешит помочь</text>
    <text x="100" y="242" fontSize="29" fill="#706a60">Один герой. Два намерения. Истории, понятные без слов.</text>
    <line x1="100" y1="284" x2="2300" y2="284" stroke="#d8cfbc" strokeWidth="2" />
    {poses.map(({ pose, title, note, look }, index) => {
      const col = index % 3;
      const row = Math.floor(index / 3);
      const x = 100 + col * 780;
      const y = 325 + row * 615;
      return (
        <g key={pose}>
          <path d={`M ${x} ${y + 469} H ${x + 690}`} stroke="#d5c6ad" strokeWidth="2" />
          <g transform={`translate(${x + 232} ${y + 456}) scale(1.02)`}>
            <Hero id={`sheet-${pose}`} pose={pose} lookX={look} tailTip={pose === "surprised" ? [302, -354] : pose === "soft" ? [266, -226] : [290, -285]} />
          </g>
          <text x={x + 8} y={y + 524} fontSize="31" fontWeight="bold" fill="#243f46">{title}</text>
          <text x={x + 8} y={y + 565} fontSize="23" fill="#81776b">{note}</text>
        </g>
      );
    })}
    <text x="100" y="1561" fontSize="21" fill="#8d8070">Оригинальный 2D-риг · отдельные глаза, брови, лапы и хвост · палитра и пропорции ещё оцениваются</text>
  </svg>
);
