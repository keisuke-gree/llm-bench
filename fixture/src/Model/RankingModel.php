<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * ランキングの情報を保持するモデル。
 */
final class RankingModel
{
    public function __construct(
        public readonly int $rankingId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    /**
     * 表示用ラベルを組み立てる。
     */
    public function displayLabel(): string
    {
        return sprintf('%s (#%d)', $this->name, $this->rankingId);
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'rankingId' => $this->rankingId,
            'name' => $this->name,
        ];
    }
}
