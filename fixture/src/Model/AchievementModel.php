<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * アチーブメントの情報を保持するモデル。
 */
final class AchievementModel
{
    public function __construct(
        public readonly int $achievementId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    /**
     * 表示用ラベルを組み立てる。
     */
    public function displayLabel(): string
    {
        return sprintf('%s (#%d)', $this->name, $this->achievementId);
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'achievementId' => $this->achievementId,
            'name' => $this->name,
        ];
    }
}
