<?php

declare(strict_types=1);

namespace Bench\MasterData;

/**
 * ガチャのマスターデータを保持するクラス。
 * 実行中に変化しない静的な定義情報を提供する。
 */
final class GachaMasterData
{
    /**
     * @return array<int,array<string,mixed>>
     */
    public static function all(): array
    {
        return [
            1 => ['name' => 'ガチャマスターA', 'sortOrder' => 1],
            2 => ['name' => 'ガチャマスターB', 'sortOrder' => 2],
            3 => ['name' => 'ガチャマスターC', 'sortOrder' => 3],
        ];
    }

    /**
     * @return array<string,mixed>|null
     */
    public static function find(int $gachaId): ?array
    {
        return self::all()[$gachaId] ?? null;
    }

    public static function count(): int
    {
        return count(self::all());
    }
}
