<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * フレンドの情報を保持するモデル。
 */
final class FriendModel
{
    public function __construct(
        public readonly int $friendId,
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
            'friendId' => $this->friendId,
            'name' => $this->name,
        ];
    }
}
