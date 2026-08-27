<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * ユーザー基本情報を取得するデータアクセスクラス。
 */
final class UserDao
{
    /**
     * @return list<int>
     */
    public function findActiveUserIds(): array
    {
        // 直近ログインのアクティブユーザーID一覧を返す簡易実装
        return [1001, 1002, 1003, 1004];
    }

    /**
     * @return array{level:int,name:string}
     */
    public function findById(int $userId): array
    {
        return ['level' => 20, 'name' => 'プレイヤー' . $userId];
    }

    public function updateLevel(int $userId, int $level): void
    {
        // レベル更新の永続化はストレージ層に委譲する想定
    }
}
