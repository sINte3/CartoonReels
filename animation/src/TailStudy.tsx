import type { FC } from "react";
import { Easing, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Hero, type Pose } from "./Hero";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = Easing.bezier(0.4, 0, 0.2, 1);
const keys = [0, 1, 1.7, 2.5, 3.4, 4.3, 5.2, 6.4, 7.9];

export const TailStudy: FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const broomAngle = interpolate(t, keys, [-8, -8, -8, -8, 11, -8, 2, 2, 2], { ...clamp, easing: ease });
  const angle = (broomAngle * Math.PI) / 180;
  const gripX = 867 + 335 * Math.sin(angle);
  const gripY = 1435 - 335 * Math.cos(angle);
  const heroX = interpolate(t, keys, [353, 353, 350, 346, 322, 329, 344, 350, 350], { ...clamp, easing: ease });
  const heroY = 1418 + interpolate(t, keys, [0, 0, 8, 0, -20, 7, 0, 0, 0], { ...clamp, easing: ease });
  const reach = interpolate(t, [1.4, 2.5, 5.1, 6.1], [0, 1, 1, 0], { ...clamp, easing: ease });
  const restX = 287 + Math.sin(t * 2.1) * 11;
  const restY = -290 + Math.sin(t * 2.5) * 13;
  const tailX = restX * (1 - reach) + ((gripX - heroX) / 1.5) * reach;
  const tailY = restY * (1 - reach) + ((gripY - heroY) / 1.5) * reach;
  const pose: Pose = t < 1.7 ? "proud" : t < 2.8 ? "caught" : t < 4.45 ? "surprised" : t < 6.0 ? "deadpan" : "soft";
  const lookX = interpolate(t, [0, 0.8, 1.6, 6.3, 7.2], [0, 0, 1, 1, 0.45], clamp);
  const blink = interpolate(t, [0, 0.5, 0.58, 0.7, 6.8, 6.9, 7.02], [0, 0, 1, 0, 0, 1, 0], clamp);
  const squash = interpolate(t, keys, [0, 0, 0.04, 0, -0.035, 0.02, 0, 0, 0], { ...clamp, easing: ease });
  const wrap = interpolate(t, [2.25, 2.55, 5.05, 5.35], [0, 1, 1, 0], clamp);

  return (
    <svg width="100%" height="100%" viewBox="0 0 1080 1920">
      <defs>
        <linearGradient id="wall" x1="0" y1="0" x2="0" y2="1">
          <stop stopColor="#f3e8ce" /><stop offset="1" stopColor="#e5d4b5" />
        </linearGradient>
        <linearGradient id="floor" x1="0" y1="0" x2="0.6" y2="1">
          <stop stopColor="#c7b69c" /><stop offset="1" stopColor="#a99c89" />
        </linearGradient>
        <linearGradient id="light" x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#fff7d8" stopOpacity="0.6" /><stop offset="1" stopColor="#fff7d8" stopOpacity="0" />
        </linearGradient>
      </defs>
      <rect width="1080" height="1350" fill="url(#wall)" />
      <rect y="1350" width="1080" height="570" fill="url(#floor)" />
      <rect x="0" y="1316" width="1080" height="35" fill="#d3bea0" />
      <path d="M 0 1351 H 1080" stroke="#b6a181" strokeWidth="4" />
      <path d="M 0 1605 L 1080 1480 M 0 1830 L 1080 1615" stroke="#a59682" strokeWidth="3" opacity="0.38" />
      <path d="M 0 340 L 980 1275 L 1080 1560 L 0 1020 Z" fill="url(#light)" />

      {/* A compact, lived-in corner: window, framed doodle and plant. */}
      <rect x="-85" y="338" width="385" height="430" rx="32" fill="#c6ac84" />
      <rect x="-62" y="360" width="338" height="380" rx="19" fill="#b4d6cc" />
      <path d="M -60 603 Q 85 516 275 603 V 738 H -60 Z" fill="#86afa1" />
      <path d="M -60 660 Q 98 558 275 657 V 738 H -60 Z" fill="#65968a" />
      <path d="M 104 360 V 740 M -62 548 H 276" stroke="#e6d2ab" strokeWidth="17" />
      <path d="M -82 760 H 300" stroke="#ae8d68" strokeWidth="20" strokeLinecap="round" />
      <rect x="713" y="506" width="220" height="255" rx="10" fill="#a98b6c" transform="rotate(5 823 633)" />
      <g transform="rotate(5 823 633)">
        <rect x="730" y="523" width="186" height="222" fill="#f5ebd4" />
        <path d="M 772 680 Q 822 539 870 680 Z" fill="#e4a183" />
        <circle cx="790" cy="576" r="17" fill="#c9b266" />
        <path d="M 755 699 H 892" stroke="#93a895" strokeWidth="8" />
      </g>

      <g transform="translate(96 1288)">
        <path d="M -43 -62 H 44 L 29 26 H -28 Z" fill="#bd7864" stroke="#9c6455" strokeWidth="4" />
        <path d="M 0 -64 Q -23 -149 -53 -174 Q -58 -97 -8 -75 M 0 -64 Q 44 -149 58 -179 Q 81 -94 8 -72 M 0 -72 Q -3 -184 15 -209 Q 41 -134 1 -73" fill="#688f75" />
      </g>

      <ellipse cx="572" cy="1480" rx="315" ry="70" fill="#71665d" opacity="0.13" />
      <path d="M 194 1502 L 632 1439 L 852 1552 L 408 1645 Z" fill="#9e776e" opacity="0.25" />
      <path d="M 194 1489 L 632 1426 L 852 1539 L 408 1632 Z" fill="#bd8271" stroke="#9a6a62" strokeWidth="4" />
      <path d="M 242 1495 L 623 1443 L 801 1534 L 418 1611 Z" fill="none" stroke="#e7b797" strokeWidth="13" />
      <path d="M 258 1517 L 632 1465 M 337 1553 L 711 1502 M 416 1588 L 788 1538" stroke="#a77068" strokeWidth="5" opacity="0.7" />

      <g transform={`rotate(${broomAngle} 867 1435)`}>
        <ellipse cx="867" cy="1450" rx="91" ry="18" fill="#71645a" opacity="0.2" />
        <path d="M 867 1400 V 977" stroke="#795d45" strokeWidth="27" strokeLinecap="round" />
        <path d="M 863 1397 V 981" stroke="#d9b985" strokeWidth="17" strokeLinecap="round" />
        <path d="M 807 1411 Q 867 1384 927 1411 L 948 1463 Q 868 1481 787 1463 Z" fill="#c5a15a" stroke="#7b6649" strokeWidth="5" />
        <path d="M 806 1415 H 929" stroke="#786265" strokeWidth="19" strokeLinecap="round" />
        {[804, 823, 843, 864, 885, 906, 927].map((x) => <path key={x} d={`M ${x} 1430 l -7 32`} stroke="#9b7d45" strokeWidth="4" strokeLinecap="round" />)}
      </g>

      <g transform={`translate(${heroX} ${heroY}) scale(1.5)`}>
        <Hero id="study-hero" pose={pose} lookX={lookX} lookY={0.1} blink={blink} tailTip={[tailX, tailY]} squash={squash} />
      </g>
      {/* Restore the visible handle through the grip, then overlap it with the near fold. */}
      <g opacity={wrap} transform={`rotate(${broomAngle} ${gripX} ${gripY})`}>
        <path d={`M ${gripX} ${gripY - 43} V ${gripY + 43}`} stroke="#795d45" strokeWidth="27" strokeLinecap="round" />
        <path d={`M ${gripX - 4} ${gripY - 43} V ${gripY + 43}`} stroke="#d9b985" strokeWidth="17" strokeLinecap="round" />
        <path d={`M ${gripX - 33} ${gripY + 3} Q ${gripX} ${gripY + 40} ${gripX + 33} ${gripY + 3}`} fill="none" stroke="#49334f" strokeWidth="23" strokeLinecap="round" />
        <path d={`M ${gripX - 33} ${gripY + 3} Q ${gripX} ${gripY + 40} ${gripX + 33} ${gripY + 3}`} fill="none" stroke="#ed997e" strokeWidth="15" strokeLinecap="round" />
      </g>
    </svg>
  );
};
