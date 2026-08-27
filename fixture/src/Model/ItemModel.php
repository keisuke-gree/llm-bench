<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * アイテムの情報を保持するモデル。
 */
final class ItemModel
{
    public function __construct(
        public readonly int $itemId,
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
            'itemId' => $this->itemId,
            'name' => $this->name,
        ];
    }
}
