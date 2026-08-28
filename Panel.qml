import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "nmorton.bitcoin"
  ipcTarget: "nmorton.bitcoin"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: "#f7931a"
  readonly property color positive: "#39b66a"
  readonly property color negative: "#ef5350"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var blockData: null
  property var mempoolData: null
  property var feeData: null
  property var difficultyData: null
  property var priceData: null
  property string priceSource: ""
  property double lastSuccessfulFetch: 0
  property double nowMs: Date.now()
  property bool fetching: false
  property int pendingEndpoints: 0
  property int successfulEndpoints: 0
  property int failureStreak: 0
  property string lastError: ""
  property string detailMode: ""
  property int focusIndex: 0
  property bool cursorActive: false

  readonly property int refreshMinutes: {
    var value = parseInt(setting("refreshMinutes", 10), 10)
    return [0, 5, 10, 15].indexOf(value) >= 0 ? value : 10
  }
  readonly property string fiatCurrency: Model.currencyCode(setting("fiatCurrency", "usd"))
  readonly property string iconStyle: String(setting("iconStyle", "bitcoin")) === "height" ? "height" : "bitcoin"
  readonly property bool stale: Model.isStale(lastSuccessfulFetch, refreshMinutes, nowMs)
  readonly property string barLabel: iconStyle === "height" && blockData ? "₿" + Model.formatNumber(blockData.height) : "₿"
  readonly property var selectedFiatPrice: priceData && priceData.currentPrice ? Model.finiteNumber(priceData.currentPrice[fiatCurrency]) : null
  readonly property var selectedSats: Model.satsPerFiat(selectedFiatPrice)
  readonly property var priceChartValues: priceData ? Model.chartValues(priceData.sparkline, 24) : []
  readonly property string priceSourceUrl: priceSource === "CoinGecko" ? "https://www.coingecko.com/en/api" : "https://mempool.space"
  readonly property int summaryWidth: Style.space(400)
  readonly property int detailWidth: Style.space(330)

  function open() {
    root.controller.show()
    if (stale && !fetching) refresh(false)
  }

  function openFromHotkey() { open() }

  function close() {
    detailMode = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cycleCurrency() { persistSetting("fiatCurrency", Model.nextCurrency(fiatCurrency)) }
  function cycleIconStyle() { persistSetting("iconStyle", iconStyle === "bitcoin" ? "height" : "bitcoin") }
  function setRefreshMinutes(value) { persistSetting("refreshMinutes", value) }
  function openExternal(url) {
    if (url) Quickshell.execDetached(["omarchy-launch-browser", String(url)])
  }

  function showDetails(mode) {
    detailMode = detailMode === mode ? "" : mode
    if (detailMode !== "") cursorActive = false
  }

  function activateFocus() {
    if (focusIndex === 0 && blockData) showDetails("block")
    else if (focusIndex === 1 && priceData) showDetails("price")
    else if (focusIndex === 2) cycleCurrency()
    else if (focusIndex === 3) refresh(true)
    else if (focusIndex === 4) cycleIconStyle()
  }

  function moveFocus(dx, dy) {
    cursorActive = true
    if (detailMode !== "" && dx > 0) {
      detailMode = ""
      return
    }
    if (dx < 0 && detailMode === "" && focusIndex <= 1) {
      if (focusIndex === 0 && blockData) detailMode = "block"
      if (focusIndex === 1 && priceData) detailMode = "price"
      return
    }
    if (dy !== 0) focusIndex = (focusIndex + (dy > 0 ? 1 : 4)) % 5
  }

  function localPath(relativePath) {
    var url = Qt.resolvedUrl(relativePath).toString()
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  function startEndpoint(process) {
    process.reported = false
    process.validResponse = false
    process.running = false
    process.running = true
  }

  function refresh(force) {
    if (fetching) return
    fetching = true
    lastError = ""
    pendingEndpoints = 6
    successfulEndpoints = 0
    startEndpoint(blockProc)
    startEndpoint(mempoolProc)
    startEndpoint(feesProc)
    startEndpoint(difficultyProc)
    startEndpoint(coinGeckoProc)
    startEndpoint(mempoolPriceProc)
  }

  function endpointFinished(process, valid) {
    if (process.reported) return
    process.reported = true
    if (valid) successfulEndpoints++
    pendingEndpoints--
    if (pendingEndpoints > 0) return

    fetching = false
    if (successfulEndpoints > 0) {
      lastSuccessfulFetch = Date.now()
      failureStreak = 0
      retryTimer.stop()
      if (successfulEndpoints < 6)
        lastError = "Partial refresh: " + successfulEndpoints + " of 6 sources responded. Last-good values are retained."
    } else {
      failureStreak = Math.min(failureStreak + 1, 6)
      lastError = "Unable to refresh Bitcoin data. Showing the last successful values."
      retryTimer.interval = Model.retryDelayMs(failureStreak)
      retryTimer.restart()
    }
  }

  function parsed(process, value, apply) {
    if (value !== null) {
      process.validResponse = true
      apply(value)
    }
    endpointFinished(process, process.validResponse)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (stale && !fetching) refresh(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onPriceChartValuesChanged: chart.requestPaint()
  onForegroundChanged: chart.requestPaint()
  onAccentChanged: chart.requestPaint()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(true); return "ok" }
    function block(): void { root.openFromHotkey(); root.showDetails("block") }
    function price(): void { root.openFromHotkey(); root.showDetails("price") }
  }

  Process {
    id: blockProc
    property bool reported: false
    property bool validResponse: false
    command: ["curl", "-fsS", "--connect-timeout", "5", "--max-time", "15", "--retry", "1", "--retry-delay", "1", "https://mempool.space/api/v1/blocks?limit=1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parsed(blockProc, Model.parseBlock(text), function(value) { root.blockData = value })
    }
    onExited: function() { Qt.callLater(function() { root.endpointFinished(blockProc, blockProc.validResponse) }) }
  }

  Process {
    id: mempoolProc
    property bool reported: false
    property bool validResponse: false
    command: ["curl", "-fsS", "--connect-timeout", "5", "--max-time", "15", "--retry", "1", "--retry-delay", "1", "https://mempool.space/api/mempool"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parsed(mempoolProc, Model.parseMempool(text), function(value) { root.mempoolData = value })
    }
    onExited: function() { Qt.callLater(function() { root.endpointFinished(mempoolProc, mempoolProc.validResponse) }) }
  }

  Process {
    id: feesProc
    property bool reported: false
    property bool validResponse: false
    command: ["bash", root.localPath("scripts/fetch-fees.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parsed(feesProc, Model.parseFees(text), function(value) { root.feeData = value })
    }
    onExited: function() { Qt.callLater(function() { root.endpointFinished(feesProc, feesProc.validResponse) }) }
  }

  Process {
    id: difficultyProc
    property bool reported: false
    property bool validResponse: false
    command: ["curl", "-fsS", "--connect-timeout", "5", "--max-time", "15", "--retry", "1", "--retry-delay", "1", "https://mempool.space/api/v1/difficulty-adjustment"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parsed(difficultyProc, Model.parseDifficulty(text), function(value) { root.difficultyData = value })
    }
    onExited: function() { Qt.callLater(function() { root.endpointFinished(difficultyProc, difficultyProc.validResponse) }) }
  }

  Process {
    id: coinGeckoProc
    property bool reported: false
    property bool validResponse: false
    command: ["curl", "-fsS", "--connect-timeout", "5", "--max-time", "18", "--retry", "1", "--retry-delay", "2", "https://api.coingecko.com/api/v3/coins/bitcoin?localization=false&tickers=false&market_data=true&community_data=false&developer_data=false&sparkline=true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parsed(coinGeckoProc, Model.parseCoinGecko(text), function(value) {
        root.priceData = value
        root.priceSource = "CoinGecko"
      })
    }
    onExited: function() { Qt.callLater(function() { root.endpointFinished(coinGeckoProc, coinGeckoProc.validResponse) }) }
  }

  Process {
    id: mempoolPriceProc
    property bool reported: false
    property bool validResponse: false
    command: ["curl", "-fsS", "--connect-timeout", "5", "--max-time", "15", "--retry", "1", "--retry-delay", "1", "https://mempool.space/api/v1/prices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parsed(mempoolPriceProc, Model.parseMempoolPrice(text), function(value) {
        if (!coinGeckoProc.validResponse) {
          root.priceData = value
          root.priceSource = "mempool.space"
        }
      })
    }
    onExited: function() { Qt.callLater(function() { root.endpointFinished(mempoolPriceProc, mempoolPriceProc.validResponse) }) }
  }

  Timer {
    interval: root.refreshMinutes > 0 ? root.refreshMinutes * 60000 : 600000
    running: root.refreshMinutes > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    id: retryTimer
    interval: 15000
    repeat: false
    onTriggered: root.refresh(false)
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(
      root.summaryWidth
        + (root.detailMode !== "" ? root.detailWidth + Style.space(12) : 0)
        + panel.padding * 2
        + Border.left(panel.borderSpec)
        + Border.right(panel.borderSpec)
    )
    contentHeight: panel.fittedContentHeight(Math.max(summaryColumn.implicitHeight, detailColumn.implicitHeight), Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveFocus(dx, dy) }
      onActivateRequested: root.activateFocus()
      onCloseRequested: {
        if (root.detailMode !== "") root.detailMode = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh(true)
        else if (text === "b" || text === "B") root.showDetails("block")
        else if (text === "p" || text === "P") root.showDetails("price")
        else if (text === "c" || text === "C") root.cycleCurrency()
      }

      Row {
        anchors.fill: parent
        spacing: root.detailMode !== "" ? Style.space(12) : 0

        Item {
          id: detailContainer
          width: root.detailMode !== "" ? root.detailWidth : 0
          height: parent.height
          clip: true
          opacity: root.detailMode !== "" ? 1 : 0

          Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 160 } }

          Rectangle {
            width: root.detailWidth
            height: parent.height
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.065)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(14)
              contentWidth: width
              contentHeight: detailColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: detailColumn
                width: parent.width
                spacing: Style.space(10)

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    text: root.detailMode === "block" ? "BLOCK DETAILS" : "PRICE DETAILS"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    width: parent.width - closeDetail.width - parent.spacing
                  }
                  Rectangle {
                    id: closeDetail
                    width: Style.space(24)
                    height: width
                    radius: width / 2
                    color: closeMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: root.dim; font.pixelSize: Style.font.body }
                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.detailMode = "" }
                  }
                }

                PanelSeparator { width: parent.width; foreground: root.foreground }

                Column {
                  visible: root.detailMode === "block"
                  width: parent.width
                  spacing: Style.space(9)

                  Text {
                    width: parent.width
                    text: root.blockData ? "#" + Model.formatNumber(root.blockData.height) : "No block data"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }
                  DetailRow { label: "Hash"; value: root.blockData ? Model.shortHash(root.blockData.id) : "—"; mono: true }
                  DetailRow { label: "Timestamp"; value: root.blockData ? Model.formatDate(root.blockData.timestamp) : "—"; subvalue: root.blockData && root.blockData.timestamp ? Model.timeAgo(root.blockData.timestamp * 1000, root.nowMs) : "" }
                  DetailRow { label: "Size"; value: root.blockData ? Model.formatBytes(root.blockData.size) : "—" }
                  DetailRow { label: "Weight"; value: root.blockData ? Model.formatWeight(root.blockData.weight) : "—" }
                  DetailRow { label: "Transactions"; value: root.blockData ? Model.formatNumber(root.blockData.txCount) : "—" }
                  DetailRow { label: "Fee span"; value: root.blockData ? Model.feeSpan(root.blockData.feeRange) : "—" }
                  DetailRow { label: "Median fee"; value: root.blockData && root.blockData.medianFee !== null ? "~" + Model.formatFee(root.blockData.medianFee) + " sat/vB" : "—" }
                  DetailRow { label: "Total fees"; value: root.blockData ? Model.formatBtc(root.blockData.totalFeesBtc) : "—"; subvalue: root.blockData && root.priceData && root.blockData.totalFeesBtc !== null ? Model.formatPrice(root.priceData.priceUsd * root.blockData.totalFeesBtc, "usd") : "" }
                  DetailRow { label: "Subsidy + fees"; value: root.blockData ? Model.formatBtc(Model.totalRewardBtc(root.blockData)) : "—"; subvalue: root.blockData && root.priceData && Model.totalRewardBtc(root.blockData) !== null ? Model.formatPrice(root.priceData.priceUsd * Model.totalRewardBtc(root.blockData), "usd") : "" }
                  DetailRow { label: "Miner"; value: root.blockData && root.blockData.poolName ? root.blockData.poolName : "Unknown" }
                  DetailRow { label: "Difficulty"; value: root.blockData && root.blockData.difficulty !== null ? Model.groupedFixed(root.blockData.difficulty, 0) : "—" }
                }

                Column {
                  visible: root.detailMode === "price"
                  width: parent.width
                  spacing: Style.space(9)

                  Text {
                    width: parent.width
                    text: root.priceData ? Model.formatPrice(root.priceData.priceUsd, "usd") : "No price data"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }

                  Column {
                    visible: root.priceChartValues.length >= 2
                    width: parent.width
                    spacing: Style.space(4)
                    Text { text: "LAST 24H"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
                    Canvas {
                      id: chart
                      width: parent.width
                      height: Style.space(82)
                      onPaint: {
                        var context = getContext("2d")
                        context.clearRect(0, 0, width, height)
                        var values = root.priceChartValues
                        if (values.length < 2) return
                        var range = Model.chartRange(values)
                        var pad = 3
                        context.strokeStyle = root.accent
                        context.lineWidth = 1.8
                        context.beginPath()
                        for (var index = 0; index < values.length; index++) {
                          var x = pad + (width - pad * 2) * index / (values.length - 1)
                          var y = pad + (height - pad * 2) * (1 - (values[index] - range.minimum) / (range.maximum - range.minimum))
                          if (index === 0) context.moveTo(x, y)
                          else context.lineTo(x, y)
                        }
                        context.stroke()
                      }
                    }
                    Row {
                      width: parent.width
                      Text { text: root.priceChartValues.length ? Model.formatPrice(Model.chartRange(root.priceChartValues).minimum, "usd") : ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width / 2 }
                      Text { text: root.priceChartValues.length ? Model.formatPrice(Model.chartRange(root.priceChartValues).maximum, "usd") : ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width / 2; horizontalAlignment: Text.AlignRight }
                    }
                  }

                  PanelSeparator { width: parent.width; foreground: root.foreground }
                  DeltaRow { label: "24h change"; value: root.priceData ? root.priceData.change24h : null }
                  DeltaRow { label: "7d change"; value: root.priceData ? root.priceData.change7d : null }
                  DeltaRow { label: "30d change"; value: root.priceData ? root.priceData.change30d : null }
                  DetailRow { label: "24h range"; value: root.priceData && root.priceData.low24h !== null && root.priceData.high24h !== null ? Model.formatPrice(root.priceData.low24h, "usd") + " – " + Model.formatPrice(root.priceData.high24h, "usd") : "—" }
                  DetailRow { label: "All-time high"; value: root.priceData ? Model.formatPrice(root.priceData.ath, "usd") : "—"; subvalue: root.priceData ? Model.shortDate(root.priceData.athDate) : "" }
                  DetailRow { label: "All-time low"; value: root.priceData ? Model.formatPrice(root.priceData.atl, "usd") : "—"; subvalue: root.priceData ? Model.shortDate(root.priceData.atlDate) : "" }
                  DetailRow { label: "Source"; value: root.priceSource || "Unknown" }
                  DetailRow { label: "Updated"; value: root.priceData && root.priceData.lastUpdated ? Model.timeAgo(new Date(root.priceData.lastUpdated).getTime(), root.nowMs) : Model.timeAgo(root.lastSuccessfulFetch, root.nowMs) }
                  ExternalLink {
                    width: parent.width
                    label: root.priceSource === "CoinGecko" ? "Powered by CoinGecko" : "Open mempool.space"
                    url: root.priceSourceUrl
                  }
                }
              }
            }
          }
        }

        Flickable {
          id: summaryFlick
          width: Math.max(1, parent.width - detailContainer.width - parent.spacing)
          height: parent.height
          contentWidth: width
          contentHeight: summaryColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: summaryColumn
            width: parent.width
            spacing: Style.space(10)

            PanelHero {
              width: parent.width
              title: root.blockData ? "Bitcoin  #" + Model.formatNumber(root.blockData.height) : "Bitcoin"
              meta: root.fetching ? "Refreshing network and market data…" : (root.stale ? "Data is stale — press R to refresh" : "Network and market overview")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconComponent: Component {
                Text { text: "₿"; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.display; font.bold: true }
              }
            }

            InfoCard {
              selected: root.cursorActive && root.focusIndex === 0
              highlighted: root.detailMode === "block"
              implicitHeight: blockCardRow.implicitHeight + Style.space(20)
              MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: { root.cursorActive = true; root.focusIndex = 0 } onClicked: if (root.blockData) root.showDetails("block") }
              Row {
                id: blockCardRow
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10); spacing: Style.space(10)
                Rectangle {
                  width: Style.space(38); height: width; radius: Style.cornerRadius
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                  Text { anchors.centerIn: parent; text: "₿"; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
                }
                Column {
                  width: parent.width - Style.space(112)
                  spacing: Style.space(2)
                  Text { text: root.blockData ? "Block #" + Model.formatNumber(root.blockData.height) : "Block unavailable"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                  Text { text: root.blockData && root.blockData.timestamp ? Model.timeAgo(root.blockData.timestamp * 1000, root.nowMs) + "  •  click for details" : "Waiting for mempool.space"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }
                Column {
                  width: Style.space(60); spacing: Style.space(2)
                  Text { width: parent.width; text: root.blockData ? Model.formatNumber(root.blockData.txCount) : "—"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; horizontalAlignment: Text.AlignRight }
                  Text { width: parent.width; text: "txns  ◀"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignRight }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              InfoCard {
                width: (parent.width - parent.spacing) / 2
                selected: root.cursorActive && root.focusIndex === 1
                highlighted: root.detailMode === "price"
                implicitHeight: Style.space(76)
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: { root.cursorActive = true; root.focusIndex = 1 } onClicked: if (root.priceData) root.showDetails("price") }
                Column {
                  anchors.fill: parent; anchors.margins: Style.space(10); spacing: Style.space(4)
                  Row {
                    width: parent.width
                    Text { text: "PRICE"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1; width: parent.width / 2 }
                    Text { text: root.priceData ? Model.formatPercent(root.priceData.change24h) : "—"; color: root.priceData && root.priceData.change24h >= 0 ? root.positive : root.negative; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: parent.width / 2; horizontalAlignment: Text.AlignRight }
                  }
                  Text { text: root.priceData ? Model.formatPrice(root.priceData.priceUsd, "usd") : "—"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
                  Text { text: "details & chart  ◀"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }
              }

              InfoCard {
                width: (parent.width - parent.spacing) / 2
                selected: root.cursorActive && root.focusIndex === 2
                implicitHeight: Style.space(76)
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: { root.cursorActive = true; root.focusIndex = 2 } onClicked: root.cycleCurrency() }
                Column {
                  anchors.fill: parent; anchors.margins: Style.space(10); spacing: Style.space(4)
                  Text { text: Model.satsLabel(root.fiatCurrency); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
                  Text { text: root.selectedSats === null ? "—" : Model.formatNumber(root.selectedSats); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
                  Text { text: root.fiatCurrency.toUpperCase() + "  •  click to cycle"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }
              }
            }

            InfoCard {
              implicitHeight: feeColumn.implicitHeight + Style.space(20)
              Column {
                id: feeColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.space(10); spacing: Style.space(8)
                Row {
                  width: parent.width
                  Text { text: "RECOMMENDED FEES"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1; width: parent.width / 2 }
                  Text { text: "sat/vB"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width / 2; horizontalAlignment: Text.AlignRight }
                }
                Row {
                  width: parent.width; spacing: Style.space(8)
                  FeeCell { label: "LOW"; value: root.feeData ? Model.formatFee(root.feeData.hourFee) : "—"; dotColor: root.positive }
                  FeeCell { label: "MED"; value: root.feeData ? Model.formatFee(root.feeData.halfHourFee) : "—"; dotColor: "#e0b43c" }
                  FeeCell { label: "HIGH"; value: root.feeData ? Model.formatFee(root.feeData.fastestFee) : "—"; dotColor: root.negative }
                }
              }
            }

            InfoCard {
              implicitHeight: networkColumn.implicitHeight + Style.space(20)
              Column {
                id: networkColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.space(10); spacing: Style.space(8)
                Row {
                  width: parent.width
                  Text { text: "DIFFICULTY EPOCH " + (root.blockData ? Model.currentEpoch(root.blockData.height) : "—"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1; width: parent.width * 0.65 }
                  Text { text: root.difficultyData ? Model.formatPercent(root.difficultyData.difficultyChange) : "—"; color: root.difficultyData && root.difficultyData.difficultyChange >= 0 ? root.positive : root.negative; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; width: parent.width * 0.35; horizontalAlignment: Text.AlignRight }
                }
                Rectangle {
                  width: parent.width; height: Style.space(6); radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                  Rectangle { width: parent.width * (root.difficultyData && root.difficultyData.progressPercent !== null ? Model.clamp(root.difficultyData.progressPercent, 0, 100) / 100 : 0); height: parent.height; radius: height / 2; color: root.accent; Behavior on width { NumberAnimation { duration: 300 } } }
                }
                Row {
                  width: parent.width
                  MiniStat { label: "PROGRESS"; value: root.difficultyData && root.difficultyData.progressPercent !== null ? Math.round(root.difficultyData.progressPercent) + "%" : "—" }
                  MiniStat { label: "RETARGET"; value: root.difficultyData ? Model.remainingTime(root.difficultyData.remainingBlocks, root.difficultyData.timeAvg) : "—" }
                  MiniStat { label: "AVG BLOCK"; value: root.difficultyData ? Model.averageBlockTime(root.difficultyData.timeAvg) : "—" }
                }
                Row {
                  width: parent.width
                  Text { text: root.mempoolData ? "Mempool: " + Model.formatNumber(root.mempoolData.count) + " tx  •  " + Model.formatVsize(root.mempoolData.vsize) : "Mempool unavailable"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width * 0.62 }
                  Text { text: root.difficultyData && root.difficultyData.estimatedRetargetDate ? "Est. " + Model.formatDate(root.difficultyData.estimatedRetargetDate) : ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width * 0.38; horizontalAlignment: Text.AlignRight }
                }
              }
            }

            Text {
              visible: root.lastError !== ""
              width: parent.width
              text: "⚠  " + root.lastError
              color: root.negative
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              Text { text: root.fetching ? "Refreshing…" : (root.stale ? "STALE  •  " : "") + "Updated " + Model.timeAgo(root.lastSuccessfulFetch, root.nowMs); color: root.stale ? root.accent : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width * 0.58 }
              Text { text: root.priceSource ? "Price: " + root.priceSource : ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width * 0.42; horizontalAlignment: Text.AlignRight }
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }

            ActionRow {
              selected: root.cursorActive && root.focusIndex === 3
              icon: root.fetching ? "󰑓" : "󰑐"
              title: root.fetching ? "Refreshing…" : "Refresh now"
              subtitle: "R or middle-click the bar icon"
              enabled: !root.fetching
              onTriggered: root.refresh(true)
            }

            ActionRow {
              selected: root.cursorActive && root.focusIndex === 4
              icon: "󰍹"
              title: "Bar label: " + (root.iconStyle === "height" ? "block height" : "Bitcoin symbol")
              subtitle: "Right-click the bar icon to switch"
              onTriggered: root.cycleIconStyle()
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text { text: "AUTO REFRESH"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
              Row {
                width: parent.width; spacing: Style.space(6)
                Repeater {
                  model: [{ value: 0, label: "Manual" }, { value: 5, label: "5 min" }, { value: 10, label: "10 min" }, { value: 15, label: "15 min" }]
                  Rectangle {
                    required property var modelData
                    width: (parent.width - Style.space(18)) / 4
                    height: Style.space(30)
                    radius: Style.cornerRadius
                    color: root.refreshMinutes === modelData.value ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, refreshMouse.containsMouse ? 0.10 : 0.055)
                    border.width: root.refreshMinutes === modelData.value ? 1 : 0
                    border.color: root.accent
                    Text { anchors.centerIn: parent; text: modelData.label; color: root.refreshMinutes === modelData.value ? root.accent : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: root.refreshMinutes === modelData.value }
                    MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setRefreshMinutes(modelData.value) }
                  }
                }
              }
            }

            ExternalLink {
              width: parent.width
              label: "Open mempool.space"
              url: "https://mempool.space"
            }

            Text {
              width: parent.width
              text: "Data: mempool.space + CoinGecko  •  No accounts, API keys, analytics, or tracking"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }

  component ExternalLink: Rectangle {
    id: externalLink
    property string label: ""
    property string url: ""
    height: Style.space(26)
    radius: Style.cornerRadius
    color: linkMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : "transparent"
    Text {
      anchors.centerIn: parent
      text: "↗  " + externalLink.label
      color: linkMouse.containsMouse ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: linkMouse.containsMouse
    }
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openExternal(externalLink.url)
    }
  }

  component InfoCard: Rectangle {
    property bool selected: false
    property bool highlighted: false
    width: parent ? parent.width : 0
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)
    border.width: selected || highlighted ? 1 : 0
    border.color: highlighted ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.60)
  }

  component DetailRow: Column {
    property string label: ""
    property string value: "—"
    property string subvalue: ""
    property bool mono: false
    width: parent ? parent.width : 0
    spacing: Style.space(2)
    Row {
      width: parent.width
      Text { text: parent.parent.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width * 0.40 }
      Text { text: parent.parent.value; color: root.foreground; font.family: parent.parent.mono ? "monospace" : root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; width: parent.width * 0.60; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle }
    }
    Text { visible: text !== ""; width: parent.width; text: parent.subvalue; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignRight }
  }

  component DeltaRow: Row {
    property string label: ""
    property var value: null
    width: parent ? parent.width : 0
    Text { text: parent.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; width: parent.width / 2 }
    Text { text: Model.formatPercent(parent.value); color: parent.value !== null && parent.value >= 0 ? root.positive : root.negative; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; width: parent.width / 2; horizontalAlignment: Text.AlignRight }
  }

  component FeeCell: Rectangle {
    id: feeCell
    property string label: ""
    property string value: "—"
    property color dotColor: root.dim
    width: (parent.width - parent.spacing * 2) / 3
    height: Style.space(52)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.045)
    Column {
      anchors.centerIn: parent; spacing: Style.space(3)
      Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(4); Rectangle { width: Style.space(6); height: width; radius: width / 2; color: feeCell.dotColor } Text { text: feeCell.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption } }
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: feeCell.value; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
    }
  }

  component MiniStat: Column {
    property string label: ""
    property string value: "—"
    width: parent ? parent.width / 3 : 0
    spacing: Style.space(2)
    Text { width: parent.width; text: parent.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
    Text { width: parent.width; text: parent.value; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; horizontalAlignment: Text.AlignHCenter }
  }

  component ActionRow: Rectangle {
    id: actionRow
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    signal triggered()
    width: parent ? parent.width : 0
    height: Style.space(48)
    radius: Style.cornerRadius
    color: selected || actionMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
    opacity: enabled ? 1 : 0.5
    Row {
      anchors.fill: parent; anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8); spacing: Style.space(9)
      Text { anchors.verticalCenter: parent.verticalCenter; text: actionRow.icon; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.heading; width: Style.space(24); horizontalAlignment: Text.AlignHCenter }
      Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(33); spacing: Style.space(1); Text { text: actionRow.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body } Text { text: actionRow.subtitle; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption } }
    }
    MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: actionRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; enabled: actionRow.enabled; onClicked: actionRow.triggered() }
  }
}
