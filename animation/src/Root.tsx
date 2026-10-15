import { Composition, Still } from "remotion";
import { CharacterSheet } from "./CharacterSheet";
import { TailStudy } from "./TailStudy";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Still id="CharacterSheet" component={CharacterSheet} width={2400} height={1600} />
      <Composition id="TailStudy" component={TailStudy} width={1080} height={1920} fps={24} durationInFrames={192} />
    </>
  );
};
