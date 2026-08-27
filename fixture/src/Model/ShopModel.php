<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * ショップの情報を保持するモデル。
 */
final class ShopModel
{
    public function __construct(
        public readonly int $shopId,
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
            'shopId' => $this->shopId,
            'name' => $this->name,
        ];
    }
}
