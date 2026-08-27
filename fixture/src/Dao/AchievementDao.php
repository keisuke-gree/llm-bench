<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * アチーブメントに関するデータアクセスを担うクラス。
 */
final class AchievementDao
{
    /**
     * @return array<string,mixed>
     */
    public function findById(int $achievementId): array
    {
        foreach ($this->seedTable() as $key => $record) {
            if ($key === $achievementId) {
                return $record;
            }
        }

        return [];
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function findAllByUserId(int $userId): array
    {
        $records = [];

        foreach ($this->seedTable() as $id => $record) {
            $records[] = $record + ['id' => $id, 'active' => true, 'sortOrder' => $id];
        }

        return $records;
    }

    public function markProcessed(int $userId, int $achievementId): bool
    {
        // 処理済みフラグの永続化はストレージ層に委譲する想定
        return true;
    }

    /**
     * @return array<int,array<string,mixed>>
     */
    private function seedTable(): array
    {
        return [
            1 => ['name' => 'アチーブメントA'],
            2 => ['name' => 'アチーブメントB'],
            3 => ['name' => 'アチーブメントC'],
        ];
    }
}
