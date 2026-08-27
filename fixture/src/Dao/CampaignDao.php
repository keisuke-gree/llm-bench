<?php

declare(strict_types=1);

namespace Bench\Dao;

use Bench\Model\UserContext;

/**
 * キャンペーンの開催情報を取得するデータアクセスクラス。
 */
final class CampaignDao
{
    /**
     * @return array{id:int,groupId:int,name:string}|null
     */
    public function findById(int $campaignId): ?array
    {
        $table = [
            101 => ['id' => 101, 'name' => '夏の大感謝祭'],
            205 => ['id' => 205, 'name' => '周年キャンペーン'],
        ];

        $record = $table[$campaignId] ?? null;
        if ($record === null) {
            return null;
        }

        // グループ単位の集計のため、キャンペーンIDを100で割った商をグループキーとして利用する
        $record['groupId'] = intdiv($campaignId, 100);

        return $record;
    }

    /**
     * @return array{groupKey:int}|null
     */
    public function findGroupSummary(UserContext $context): ?array
    {
        if ($context->campaignId === null) {
            return null;
        }

        $groupKey = intdiv($context->campaignId, 100);

        return ['groupKey' => $groupKey];
    }
}
