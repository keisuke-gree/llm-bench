<?php

declare(strict_types=1);

namespace Bench\MasterData;

/**
 * クエストのマスターデータを保持するクラス。
 * 実行中に変化しない静的な定義情報を提供する。
 */
final class QuestMasterData
{
    /**
     * @return array<int,array<string,mixed>>
     */
    public static function all(): array
    {
        return [
            1 => ['name' => 'クエストマスターA', 'sortOrder' => 1],
            2 => ['name' => 'クエストマスターB', 'sortOrder' => 2],
            3 => ['name' => 'クエストマスターC', 'sortOrder' => 3],
        ];
    }

    /**
     * @return array<string,mixed>|null
     */
    public static function find(int $questId): ?array
    {
        return self::all()[$questId] ?? null;
    }

    public static function count(): int
    {
        return count(self::all());
    }
}
