<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * キャンペーンへのエントリー状態を表すモデル。
 */
final class CampaignEntryModel
{
    public function __construct(
        private int $campaignId,
        private int $userId,
    ) {
    }

    /**
     * @return array{campaignId:int,userId:int}
     */
    public function toArray(): array
    {
        return ['campaignId' => $this->campaignId, 'userId' => $this->userId];
    }
}
