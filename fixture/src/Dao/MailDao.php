<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * お知らせメールに関するデータアクセスを担うクラス。
 */
final class MailDao
{
    /**
     * @return array<string,mixed>
     */
    public function findById(int $mailId): array
    {
        foreach ($this->seedTable() as $key => $record) {
            if ($key === $mailId) {
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

    public function markProcessed(int $userId, int $mailId): bool
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
            1 => ['name' => 'お知らせメールA'],
            2 => ['name' => 'お知らせメールB'],
            3 => ['name' => 'お知らせメールC'],
        ];
    }
}
