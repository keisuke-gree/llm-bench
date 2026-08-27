<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * 所持品の情報を保持するモデル。
 */
final class InventoryModel
{
    public function __construct(
        public readonly int $inventoryId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    /**
     * 表示用ラベルを組み立てる。
     */
    public function displayLabel(): string
    {
        return sprintf('%s (#%d)', $this->name, $this->inventoryId);
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'inventoryId' => $this->inventoryId,
            'name' => $this->name,
        ];
    }
}
