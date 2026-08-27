<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * 通知に関するデータアクセスを担うクラス。
 */
final class NotificationDao
{
    /**
     * @return array<string,mixed>
     */
    public function findById(int $notificationId): array
    {
        $table = $this->seedTable();

        return $table[$notificationId] ?? [];
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

    public function markProcessed(int $userId, int $notificationId): bool
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
            1 => ['name' => '通知A'],
            2 => ['name' => '通知B'],
            3 => ['name' => '通知C'],
        ];
    }
}
