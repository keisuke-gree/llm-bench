<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * ショップに関するデータアクセスを担うクラス。
 */
final class ShopDao
{
    /**
     * @return array<string,mixed>
     */
    public function findById(int $shopId): array
    {
        $table = $this->seedTable();

        return $table[$shopId] ?? [];
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

    public function markProcessed(int $userId, int $shopId): bool
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
            1 => ['name' => 'ショップA'],
            2 => ['name' => 'ショップB'],
            3 => ['name' => 'ショップC'],
        ];
    }
}
