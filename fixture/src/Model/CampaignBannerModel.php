<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * キャンペーンバナー表示用の情報を組み立てるモデル。
 */
final class CampaignBannerModel
{
    public function __construct(private UserContext $context)
    {
    }

    /**
     * バナー画像のファイル名にキャンペーンIDを埋め込んで返す。
     */
    public function buildImagePath(): string
    {
        return "assets/campaign/banner_{$this->context->campaignId}.png";
    }

    public function buildTitleKey(): string
    {
        return "campaign_{$this->context->campaignId}_title";
    }
}
