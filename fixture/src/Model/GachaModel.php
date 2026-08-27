<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * ガチャの情報を保持するモデル。
 */
final class GachaModel
{
    public function __construct(
        public readonly int $gachaId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    /**
     * 表示用ラベルを組み立てる。
     */
    public function displayLabel(): string
    {
        return sprintf('%s (#%d)', $this->name, $this->gachaId);
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'gachaId' => $this->gachaId,
            'name' => $this->name,
        ];
    }
}
