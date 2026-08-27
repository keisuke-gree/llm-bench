<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\CampaignDao;
use Bench\Model\UserContext;

/**
 * ユーザーコンテキストからキャンペーン開催情報を解決するクラス。
 */
final class CampaignResolver
{
    public function __construct(private CampaignDao $campaignDao)
    {
    }

    /**
     * @return array{id:int,groupId:int,name:string}|null
     */
    public function resolve(UserContext $context): ?array
    {
        if ($context->campaignId === null) {
            return null;
        }

        return $this->resolveCampaign($context->campaignId);
    }

    /**
     * キャンペーンIDから開催情報を取得する。
     */
    private function resolveCampaign(int $campaignId): ?array
    {
        return $this->campaignDao->findById($campaignId);
    }
}
