.pragma library

var FIAT_CURRENCIES = ["usd", "eur", "gbp", "jpy", "cad", "aud", "chf", "cny", "hkd", "sgd"]

function finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null
  var number = Number(value)
  return isFinite(number) ? number : null
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function currencyCode(currency) {
  var value = String(currency || "usd").toLowerCase()
  return FIAT_CURRENCIES.indexOf(value) >= 0 ? value : "usd"
}

function currencySymbol(currency) {
  switch (currencyCode(currency)) {
  case "usd": return "$"
  case "eur": return "€"
  case "gbp": return "£"
  case "jpy": return "¥"
  case "cad": return "C$"
  case "aud": return "A$"
  case "chf": return "CHF "
  case "cny": return "¥"
  case "hkd": return "HK$"
  case "sgd": return "S$"
  }
  return ""
}

function satsLabel(currency) {
  var code = currencyCode(currency)
  return code === "usd" ? "SATS/$" : "SATS/" + code.toUpperCase()
}

function nextCurrency(currency) {
  var index = FIAT_CURRENCIES.indexOf(currencyCode(currency))
  return FIAT_CURRENCIES[(index + 1) % FIAT_CURRENCIES.length]
}

function groupedInteger(value) {
  var text = String(Math.round(Math.abs(Number(value) || 0)))
  var result = ""
  while (text.length > 3) {
    result = "," + text.slice(-3) + result
    text = text.slice(0, -3)
  }
  return (Number(value) < 0 ? "-" : "") + text + result
}

function formatNumber(value) {
  return finiteNumber(value) === null ? "—" : groupedInteger(value)
}

function groupedFixed(value, digits) {
  var number = finiteNumber(value)
  if (number === null) return "—"
  var fixed = Math.abs(number).toFixed(digits).split(".")
  var integer = groupedInteger(Number(fixed[0]))
  return (number < 0 ? "-" : "") + integer + (digits > 0 ? "." + fixed[1] : "")
}

function formatPrice(value, currency) {
  var number = finiteNumber(value)
  if (number === null) return "—"
  var digits = currencyCode(currency) === "jpy" ? 0 : 2
  return currencySymbol(currency) + groupedFixed(number, digits)
}

function formatPercent(value) {
  var number = finiteNumber(value)
  if (number === null) return "—"
  return (number >= 0 ? "+" : "") + number.toFixed(1) + "%"
}

function formatFee(value) {
  var number = finiteNumber(value)
  if (number === null) return "—"
  return number.toFixed(Math.abs(number - Math.round(number)) < 0.0001 ? 0 : 1)
}

function formatBytes(value) {
  var number = finiteNumber(value)
  return number === null ? "—" : (number / 1000000).toFixed(2) + " MB"
}

function formatWeight(value) {
  var number = finiteNumber(value)
  return number === null ? "—" : (number / 1000000).toFixed(2) + " MWU"
}

function formatVsize(value) {
  var number = finiteNumber(value)
  return number === null ? "—" : (number / 1000000).toFixed(1) + " MvB"
}

function formatBtc(value) {
  var number = finiteNumber(value)
  return number === null ? "—" : groupedFixed(number, 3) + " BTC"
}

function satsPerFiat(price) {
  var number = finiteNumber(price)
  return number !== null && number > 0 ? Math.round(100000000 / number) : null
}

function shortHash(hash) {
  var value = String(hash || "")
  return value.length > 16 ? value.slice(0, 6) + "…" + value.slice(-6) : (value || "—")
}

function parseJson(text) {
  try { return JSON.parse(String(text || "")) } catch (error) { return null }
}

function firstDefined(object, keys) {
  for (var index = 0; index < keys.length; index++) {
    var value = object[keys[index]]
    if (value !== undefined && value !== null) return value
  }
  return null
}

function parseBlock(text) {
  var value = parseJson(text)
  var block = value instanceof Array ? value[0] : null
  if (!block || finiteNumber(block.height) === null) return null
  var extras = block.extras || {}
  var pool = firstDefined(extras, ["pool", "miner", "miningPool"])
  var poolName = typeof pool === "string" ? pool : (pool ? (pool.name || pool.poolName || pool.slug || "") : "")
  var totalFees = firstDefined(extras, ["totalFees", "total_fees"])
  var reward = firstDefined(extras, ["reward", "subsidy", "subsidy_fee", "total_reward", "totalReward"])
  return {
    id: String(block.id || ""),
    height: Number(block.height),
    timestamp: finiteNumber(block.timestamp),
    txCount: finiteNumber(block.tx_count),
    size: finiteNumber(block.size),
    weight: finiteNumber(block.weight),
    difficulty: finiteNumber(block.difficulty),
    feeRange: extras.feeRange || extras.fee_range || [],
    medianFee: finiteNumber(firstDefined(extras, ["medianFee", "median_fee"])),
    totalFeesBtc: finiteNumber(totalFees) === null ? null : Number(totalFees) / 100000000,
    rewardBtc: finiteNumber(reward) === null ? null : Number(reward) / 100000000,
    poolName: String(poolName || "")
  }
}

function parseMempool(text) {
  var value = parseJson(text)
  if (!value || finiteNumber(value.count) === null) return null
  return { count: Number(value.count), vsize: finiteNumber(value.vsize) }
}

function parseFees(text) {
  var value = parseJson(text)
  if (!value || finiteNumber(value.fastestFee) === null) return null
  return {
    fastestFee: Number(value.fastestFee),
    halfHourFee: finiteNumber(value.halfHourFee),
    hourFee: finiteNumber(value.hourFee)
  }
}

function parseDifficulty(text) {
  var value = parseJson(text)
  if (!value || typeof value !== "object") return null
  var result = {
    progressPercent: finiteNumber(value.progressPercent),
    remainingBlocks: finiteNumber(value.remainingBlocks),
    estimatedRetargetDate: finiteNumber(value.estimatedRetargetDate),
    difficultyChange: finiteNumber(value.difficultyChange),
    timeAvg: finiteNumber(value.timeAvg)
  }
  return result.progressPercent === null && result.remainingBlocks === null && result.timeAvg === null ? null : result
}

function parseCoinGecko(text) {
  var value = parseJson(text)
  var market = value && value.market_data
  if (!market || !market.current_price || finiteNumber(market.current_price.usd) === null) return null
  return {
    currentPrice: market.current_price,
    priceUsd: Number(market.current_price.usd),
    change24h: finiteNumber(market.price_change_percentage_24h),
    change7d: finiteNumber(market.price_change_percentage_7d),
    change30d: finiteNumber(market.price_change_percentage_30d),
    high24h: finiteNumber(market.high_24h && market.high_24h.usd),
    low24h: finiteNumber(market.low_24h && market.low_24h.usd),
    ath: finiteNumber(market.ath && market.ath.usd),
    athDate: String((market.ath_date && market.ath_date.usd) || ""),
    atl: finiteNumber(market.atl && market.atl.usd),
    atlDate: String((market.atl_date && market.atl_date.usd) || ""),
    lastUpdated: String(market.last_updated || ""),
    sparkline: market.sparkline_7d && market.sparkline_7d.price instanceof Array ? market.sparkline_7d.price : []
  }
}

function parseMempoolPrice(text) {
  var value = parseJson(text)
  var usd = value ? finiteNumber(value.USD) : null
  return usd === null ? null : { currentPrice: { usd: usd }, priceUsd: usd }
}

function feeSpan(values) {
  if (!(values instanceof Array) || values.length === 0) return "—"
  var valid = values.map(Number).filter(function(value) { return isFinite(value) })
  if (valid.length === 0) return "—"
  return formatFee(Math.min.apply(null, valid)) + " – " + formatFee(Math.max.apply(null, valid)) + " sat/vB"
}

function blockSubsidy(height) {
  var halvings = Math.floor((finiteNumber(height) || 0) / 210000)
  return halvings >= 64 ? 0 : 50 / Math.pow(2, halvings)
}

function totalRewardBtc(block) {
  if (!block) return null
  if (finiteNumber(block.rewardBtc) !== null) return Number(block.rewardBtc)
  if (finiteNumber(block.totalFeesBtc) === null) return null
  return blockSubsidy(block.height) + Number(block.totalFeesBtc)
}

function currentEpoch(height) {
  var number = finiteNumber(height)
  return number === null ? null : Math.floor(number / 2016) + 1
}

function averageBlockTime(milliseconds) {
  var number = finiteNumber(milliseconds)
  if (number === null) return "—"
  var seconds = Math.round(number / 1000)
  return Math.floor(seconds / 60) + "m " + (seconds % 60) + "s"
}

function remainingTime(remainingBlocks, millisecondsPerBlock) {
  var blocks = finiteNumber(remainingBlocks)
  if (blocks === null) return "—"
  var averageMs = finiteNumber(millisecondsPerBlock)
  var minutes = blocks * (averageMs === null ? 10 : averageMs / 60000)
  if (minutes < 1440) return "~" + Math.max(1, Math.round(minutes / 60)) + "h"
  return "~" + (minutes / 1440).toFixed(1) + " days"
}

function timeAgo(timestampMs, nowMs) {
  var stamp = finiteNumber(timestampMs)
  if (stamp === null) return "never"
  var seconds = Math.max(0, Math.floor(((finiteNumber(nowMs) || Date.now()) - stamp) / 1000))
  if (seconds < 5) return "just now"
  if (seconds < 60) return seconds + "s ago"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
  return Math.floor(seconds / 86400) + "d ago"
}

function formatDate(value) {
  if (value === null || value === undefined || value === "") return "—"
  var date = typeof value === "number" ? new Date(value > 100000000000 ? value : value * 1000) : new Date(value)
  if (isNaN(date.getTime())) return "—"
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " + pad(date.getHours()) + ":" + pad(date.getMinutes())
}

function shortDate(value) {
  if (!value) return "—"
  var date = new Date(value)
  if (isNaN(date.getTime())) return "—"
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear()
}

function pad(value) { return value < 10 ? "0" + value : String(value) }

function chartValues(values, count) {
  if (!(values instanceof Array)) return []
  var valid = values.map(Number).filter(function(value) { return isFinite(value) })
  return valid.slice(-Math.max(2, count || 24))
}

function chartRange(values) {
  if (!(values instanceof Array) || values.length === 0) return { minimum: 0, maximum: 1 }
  var minimum = Math.min.apply(null, values)
  var maximum = Math.max.apply(null, values)
  if (maximum - minimum < 0.0001) maximum = minimum + 0.0001
  return { minimum: minimum, maximum: maximum }
}

function retryDelayMs(failureStreak) {
  var streak = Math.max(1, Math.floor(finiteNumber(failureStreak) || 1))
  return Math.min(300000, 15000 * Math.pow(2, streak - 1))
}

function staleThresholdMs(refreshMinutes) {
  var minutes = finiteNumber(refreshMinutes)
  return Math.max((minutes && minutes > 0 ? minutes * 1.5 * 60000 : 15 * 60000), 180000)
}

function isStale(lastSuccessMs, refreshMinutes, nowMs) {
  var last = finiteNumber(lastSuccessMs)
  return last === null || (finiteNumber(nowMs) || Date.now()) - last > staleThresholdMs(refreshMinutes)
}
