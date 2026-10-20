import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/ui/sheet", () => ({
  Sheet: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import { AriaVoicePicker } from "./aria-voice-picker";
import { ARIA_VOICE_RECIPES, applyVoiceProfile, speakRequestBody } from "@/lib/aria-voice";

function SettingsRowStub({
  label,
  value,
  onClick,
}: {
  label: string;
  value?: React.ReactNode;
  onClick?: () => void;
}) {
  return (
    <button type="button" onClick={onClick}>
      <span>{label}</span>
      {value}
    </button>
  );
}

describe("AriaVoicePicker", () => {
  it("switching profile changes the next speak request voice id", () => {
    const warm = { ...ARIA_VOICE_RECIPES[0], voiceId: "voice-warm-1" };
    const ember = { ...ARIA_VOICE_RECIPES[4], voiceId: "voice-ember-1" };
    const onSelect = vi.fn();

    render(
      <AriaVoicePicker
        SettingsRow={SettingsRowStub}
        selection={applyVoiceProfile({}, warm)}
        onSelect={onSelect}
      />
    );

    fireEvent.click(screen.getByRole("radio", { name: /Ember/i }));
    expect(onSelect).toHaveBeenCalled();
    const next = onSelect.mock.calls[0][0];
    expect(next.profileId).toBe("ember");
    const body = speakRequestBody("I'm ARIA.", applyVoiceProfile({}, ember));
    expect(body.voice_id).toBe("voice-ember-1");
    expect(body.voice_id).not.toBe("voice-warm-1");
  });
});
