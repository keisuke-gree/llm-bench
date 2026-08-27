<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * チュートリアルの情報を保持するモデル。
 */
final class TutorialModel
{
    public function __construct(
        public readonly int $tutorialId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    public function isAvailable(\DateTimeImmutable $now): bool
    {
        return $this->registeredAt <= $now;
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'tutorialId' => $this->tutorialId,
            'name' => $this->name,
        ];
    }
}
