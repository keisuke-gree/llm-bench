<?php

declare(strict_types=1);

namespace Bench\MasterData;

/**
 * アイテムのマスターデータを保持するクラス。
 * 実行中に変化しない静的な定義情報を提供する。
 */
final class ItemMasterData
{
    /**
     * @return array<int,array<string,mixed>>
     */
    public static function all(): array
    {
        return [
            1 => ['name' => 'アイテムマスターA', 'sortOrder' => 1],
            2 => ['name' => 'アイテムマスターB', 'sortOrder' => 2],
            3 => ['name' => 'アイテムマスターC', 'sortOrder' => 3],
        ];
    }

    /**
     * @return array<string,mixed>|null
     */
    public static function find(int $itemId): ?array
    {
        return self::all()[$itemId] ?? null;
    }

    public static function count(): int
    {
        return count(self::all());
    }
}
