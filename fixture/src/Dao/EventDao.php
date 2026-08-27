<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * イベントの定義情報・進行状況を取得するデータアクセスクラス。
 */
final class EventDao
{
    /**
     * @return array{baseReward:int,name:string}
     */
    public function findById(int $eventId): array
    {
        $table = [
            10 => ['baseReward' => 200, 'name' => '討伐イベント'],
            11 => ['baseReward' => 350, 'name' => '収集イベント'],
        ];

        return $table[$eventId] ?? ['baseReward' => 0, 'name' => '不明なイベント'];
    }

    /**
     * @return list<int>
     */
    public function findActiveEventIds(\DateTimeImmutable $now): array
    {
        // 現状は固定の開催中イベントIDを返す簡易実装
        return [10, 11];
    }

    public function recordEntry(int $eventId, int $userId): void
    {
        // エントリー履歴の永続化はストレージ層に委譲する想定
    }
}
