#!/usr/bin/env node

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = { console, Date, Math, JSON, Number, String, Array, isFinite }
vm.createContext(model)
vm.runInContext(source, model, { filename: "Model.js" })

assert.equal(model.finiteNumber(null), null)
assert.equal(model.finiteNumber(""), null)
assert.equal(model.finiteNumber("12.5"), 12.5)
assert.equal(model.currencyCode("CAD"), "cad")
assert.equal(model.currencyCode("nope"), "usd")
assert.equal(model.nextCurrency("usd"), "eur")
assert.equal(model.nextCurrency("sgd"), "usd")
assert.equal(model.satsLabel("usd"), "SATS/$")
assert.equal(model.satsLabel("jpy"), "SATS/JPY")
assert.equal(model.satsPerFiat(100000), 1000)
assert.equal(model.formatNumber(912345), "912,345")
assert.equal(model.formatPrice(123456.7, "usd"), "$123,456.70")
assert.equal(model.formatPercent(-2.34), "-2.3%")
assert.equal(model.blockSubsidy(840000), 3.125)
assert.equal(model.currentEpoch(0), 1)
assert.equal(model.currentEpoch(2016), 2)
assert.equal(model.shortHash("000000000000000000001234567890"), "000000…567890")

const block = model.parseBlock(JSON.stringify([{
  id: "abc",
  height: 900001,
  timestamp: 1700000000,
  tx_count: 3210,
  size: 1500000,
  weight: 3990000,
  difficulty: 12,
  extras: {
    feeRange: [1, 2, 10],
    medianFee: 2.5,
    totalFees: 25000000,
    reward: 337500000,
    pool: { name: "Test Pool" }
  }
}]))
assert.equal(block.height, 900001)
assert.equal(block.txCount, 3210)
assert.equal(block.totalFeesBtc, 0.25)
assert.equal(block.rewardBtc, 3.375)
assert.equal(block.poolName, "Test Pool")
assert.equal(model.feeSpan(block.feeRange), "1 – 10 sat/vB")

for (const rewardKey of ["reward", "subsidy", "subsidy_fee", "total_reward", "totalReward"]) {
  const aliasBlock = model.parseBlock(JSON.stringify([{
    id: "alias-test",
    height: 900001,
    extras: { [rewardKey]: 312500000 }
  }]))
  assert.equal(aliasBlock.rewardBtc, 3.125, `reward alias ${rewardKey}`)
}

const legacyBlock = model.parseBlock(JSON.stringify([{
  id: "legacy-test",
  height: 900001,
  extras: {
    fee_range: [1, 3],
    median_fee: 2,
    total_fees: 12500000,
    miner: "Legacy Pool"
  }
}]))
assert.equal(legacyBlock.totalFeesBtc, 0.125)
assert.equal(legacyBlock.medianFee, 2)
assert.equal(legacyBlock.poolName, "Legacy Pool")

const coinGecko = model.parseCoinGecko(JSON.stringify({
  market_data: {
    current_price: { usd: 100000, eur: 90000 },
    price_change_percentage_24h: 1.2,
    price_change_percentage_7d: -2.3,
    price_change_percentage_30d: 4.5,
    high_24h: { usd: 101000 },
    low_24h: { usd: 99000 },
    ath: { usd: 110000 },
    ath_date: { usd: "2025-01-01T00:00:00Z" },
    atl: { usd: 50 },
    atl_date: { usd: "2013-01-01T00:00:00Z" },
    last_updated: "2026-01-01T00:00:00Z",
    sparkline_7d: { price: [1, 2, 3, 4] }
  }
}))
assert.equal(coinGecko.priceUsd, 100000)
assert.equal(coinGecko.currentPrice.eur, 90000)
assert.equal(coinGecko.atl, 50)
assert.deepEqual(Array.from(model.chartValues(coinGecko.sparkline, 3)), [2, 3, 4])

assert.equal(model.parseBlock("not json"), null)
assert.equal(model.parseMempool("{}"), null)
assert.equal(model.averageBlockTime(600000), "10m 0s")
assert.equal(model.remainingTime(144, 600000), "~1.0 days")
assert.match(model.formatDate(1788660999540), /^2026-/)
assert.match(model.formatDate(1787940045), /^2026-/)
assert.equal(model.retryDelayMs(1), 15000)
assert.equal(model.retryDelayMs(5), 240000)
assert.equal(model.retryDelayMs(6), 300000)
assert.equal(model.retryDelayMs(20), 300000)
assert.equal(model.isStale(1000000, 10, 1000100), false)
assert.equal(model.isStale(1000000, 10, 2000000), true)

console.log("Model.js: all tests passed")
