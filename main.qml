// Version modified JFM

// Version 1.3 :
// Add directly to the layer pre-selected in settings, even if not selected

// Version 1.4 :
// Add a graphic UI with compass rose etc.
// Visual indicator for calibration level

// Version 1.5 :
// Add settings to edit the field names / add to the list of field names

// Other / won't fix

// Check what happens in the Southern hemisphere(reverse dip)
// Auto-detect declination (impossible in QField for Android??)

// See if one can also save the geometry (plane, line, plane with line) - maybe not a good idea, too dependent on user config
// Fix problem with pitch (form default overrides plugin) - probably same prb as above

// Done, check in all situations ?
// Save point to cursor (not device) location
// canvas = iface.mapCanvas()
// canvas.mapSettings.center .x, .y


import QtCore

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

import QtSensors

import org.qfield
import org.qgis
import Theme


Item {
  id: root

  property var dipFieldNames:          ["dip", "dip_angle", "pendage", "dip_ref", "P_dip", "Dip"]
  property var dipDirectionFieldNames: ["dip_direction", "dipdirection", "dip_dir", "dipdir_ref", "P_dipAzimuth", "Dip direction"]
  property var strikeFieldNames:       ["strike_rhr", "strike", "strike_ref", "P_strike", "Strike"]

  property var trendFieldNames:        ["L_plungeAzimuth", "Trend"]
  property var plungeFieldNames:       ["plunge", "plongement", "L_plunge", "Plunge"]
  property var pitchFieldNames:        ["pitch","Pitch","L_pitch"]

  property var skipFieldNames:         ["fid", "id", "objectid"]

  property var geomFieldNames:         ["ObjectGeom", "Geometry"]

  property var mainWindow: iface.mainWindow()
  property var positionSource: iface.findItemByObjectName('positionSource')
  property var dashBoard: iface.findItemByObjectName('dashBoard')
  property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')
  property var canvas: iface.mapCanvas()

  ListModel { id: pointLayerPickerModel }
  // target layer for save
  property int targetLayer: 0
  property var currentlyActiveLayer: dashBoard.activeLayer

  property var declination: position.magneticVariation

  Connections {
    target: overlayFeatureFormDrawer

    function onClosed() {
      dashBoard.activeLayer = currentlyActiveLayer
    }
  }

  function populatePointLayerPicker(){
    // From https://github.com/TyHol/Qfield_Convert_Coords/blob/main/Conversion_tools/main.qml
    // Get point layers
    var allLayers = canvas.mapSettings.layers;
    var pointLayers = []
    pointLayerPickerModel.clear()

    for (var layerId in allLayers) {
      var layer = allLayers[layerId]

      if(layer &&
          layer.geometryType &&
          layer.geometryType() === Qgis.GeometryType.Point &&
          layer.supportsEditing === true) {
        pointLayers.push(layer)
      }
    }

    // sort alphabetically
    pointLayers.sort(function(a, b) { return a.name.localeCompare(b.name) })

    // If no layers found at all, show a placeholder and bail out
    if (pointLayers.length === 0 ) {
      pointLayerPickerModel.append({ "name": qsTr("— no editable point layers —"), "isHeader": true })
     // pointLayerCombo.currentIndex = 0
      root.targetLayer = 0
      // pointLayerName = ""
      return
    }

    // Layers exist — add "Active Layer" as first selectable option
    pointLayerPickerModel.append({ "name": qsTr("Active Layer"), "isHeader": false })

    // Append to model
    for (var i = 0; i < pointLayers.length; i++)
      pointLayerPickerModel.append({ "name": pointLayers[i].name, "isHeader": false })
  }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)

    // populatePointLayerPicker()
  }

  Compass {
    id: compass
    active: true
    dataRate: 10
    property real currentHeading: 0
    property real calibrationLevel : 0

    onReadingChanged: {
      if (reading)
      {
        // Compass gives the azimuth of the (physical) top of the device.
        // If we want the azimuth of the top of the screen, we must correct that.
        // with Screen.orientation

        calibrationLevel = reading.calibrationLevel
        currentHeading = reading.azimuth
        if(currentHeading < 0) currentHeading += 360

        currentHeading += pluginSettings.magneticDeclination
        smoothCompass.doSmooth(currentHeading)
      }
    }
  }

  Item {
    id: smoothCompass

    property real heading:0

    function doSmooth(hd){
      var x_hd = Math.cos(hd * Math.PI / 180)
      var y_hd = Math.sin(hd * Math.PI / 180)

      var x_shd = Math.cos(heading * Math.PI / 180)
      var y_shd = Math.sin(heading * Math.PI / 180)

      x_shd = (pluginSettings.smoothingCompAlpha * (x_hd) ) +
          (1 - pluginSettings.smoothingCompAlpha) * (x_shd)
      y_shd = (pluginSettings.smoothingCompAlpha * (y_hd) ) +
          (1 - pluginSettings.smoothingCompAlpha) * (y_shd)

      heading = Math.atan2(y_shd,x_shd) * 180 / Math.PI
      if(heading < 0) heading += 360
    }

    function viewAngle(){
      if(Screen.orientation===1)
        return(heading)
      else if(Screen.orientation===2)
        return( (heading + 90) % 360)
      else if(Screen.orientation===4)
        return( (heading + 180) % 360 )
      else if(Screen.orientation===8)
        return( (heading + 270) % 360 )
    }

  }

  Accelerometer {
    id: accelerometer
    active: true
    dataRate: 10

    property real currentX: 0
    property real currentY: 0
    property real currentZ: 0

    onReadingChanged: {
      if (reading) {
        currentX = reading.x
        currentY = reading.y
        currentZ = reading.z

        smoothAccelerometer.doSmooth(currentX,currentY,currentZ)
        geoData.getOrientation()
      }
    }
  }

  Item {
    id: smoothAccelerometer

    property real xx:0
    property real yy:0
    property real zz:0

    function doSmooth(currentX,currentY,currentZ){
      xx = (pluginSettings.smoothingCompAlpha * currentX ) +
          (1 - pluginSettings.smoothingCompAlpha) * xx
      yy = (pluginSettings.smoothingCompAlpha * currentY ) +
          (1 - pluginSettings.smoothingCompAlpha) * yy
      zz = (pluginSettings.smoothingCompAlpha * currentZ ) +
          (1 - pluginSettings.smoothingCompAlpha) * zz
    }

  }

  Item {
    id: geoData
    // Core computation from Mark Jessel

    property real dip: 0
    property real dipDirection: 0
    property real strike: 0

    property real trend: 0
    property real plunge: 0
    property real pitch: 0

    function getOrientation(gx = smoothAccelerometer.xx,
                            gy = smoothAccelerometer.yy,
                            gz = smoothAccelerometer.zz,
                            hd = smoothCompass.heading) {
      // DIRECT METHOD: Use gravity vector and transform by compass only

      // Compass reading
      var hdRad = hd * Math.PI / 180

      // Gravity in phone frame
      var g_mag = Math.sqrt(gx*gx + gy*gy + gz*gz)
      if (g_mag < 1.0) {
        return { dip: 0, dipDirection: 0, strike: 0, trend: 0, plunge: 0 , pitch: 0}
      }

      // Normalize
      gx /= g_mag
      gy /= g_mag
      gz /= g_mag

      // Dip angle from vertical
      dip = Math.acos(Math.abs(gz)) * 180 / Math.PI

      // Transform gravity horizontal component to world coordinates
      // Phone frame: +X=right, +Y=top, +Z=out of screen
      // Compass tells us where +Y points

      // The downslope direction in phone frame is toward (gx, gy)
      // But +Y points toward azimuth, and +X points 90° right of that

      // World frame transformation:
      // If phone Y-axis points toward azimuth, then:
      // North component = gy * cos(az) + gx * cos(az + 90°)
      //                 = gy * cos(az) - gx * sin(az)
      // East component  = gy * sin(az) + gx * cos(az + 90°)
      //                 = gy * sin(az) + gx * cos(az)

      var g_north = gy * Math.cos(hdRad) - gx * Math.sin(hdRad)
      var g_east = gy * Math.sin(hdRad) + gx * Math.cos(hdRad)

      // Dip direction is where gravity's horizontal projection points
      dipDirection = Math.atan2(g_east, g_north) * 180 / Math.PI

      // Here Mark adds 180°, ostensibly for Southern Hemisphere
      // but in my tests it seems to be always required !
      // if (pluginSettings.southernHemisphere) dipDirection=(dipDirection+180)%360
      // if (dipDirection < 0) dipDirection += 360
      if (pluginSettings.southernHemisphere) {
        dipDirection=(dipDirection)
      } else {
        dipDirection=(dipDirection+180)
      }
      if (dipDirection < 0) dipDirection += 360
      if (dipDirection >= 360) dipDirection -= 360

      strike = dipDirection - 90
      if (strike < 0) strike += 360

      // Plunge = tilt of phone's long axis (Y-axis, top-to-bottom)
      // This is the component of gravity along the Y-axis

      // Plunge is angle from horizontal along Y-axis
      // When gy is large (gravity toward top/bottom), plunge is large
      // When gz is large (gravity perpendicular to screen), plunge is small
      plunge = Math.asin(Math.abs(gy)) * 180 / Math.PI

      // The trend of the line is the device heading +- 180° !
      trend = 0
      if(Math.abs(dipDirection - hd) < 90)
        trend = hd
      else
        trend = hd + 180

      if (trend > 360) trend -=360

      // Pitch
      pitch = Math.atan( Math.tan((hd-strike)*Math.PI/180 ) / Math.cos( dip*Math.PI/180 )  )
      pitch = pitch * 180/Math.PI
      pitch = (pitch+180)%180

      return { dip: dip, dipDirection: dipDirection, strike: strike, trend: trend, plunge: plunge , pitch: pitch}
    }
  }

  QfDialog {
    id: mainDialog
    parent: mainWindow.contentItem
    standardButtons: Dialog.Close

    property bool isReactive: true

    property real heading: isReactive ? smoothCompass.viewAngle() : heading

    property real strike: isReactive ? geoData.strike : strike
    property real dip: isReactive ? geoData.dip : dip
    property real dipDirection: isReactive ? geoData.dipDirection : dipDirection

    property real trend: isReactive ? geoData.trend : trend
    property real plunge: isReactive ? geoData.plunge : plunge
    property real pitch: isReactive ? geoData.pitch : pitch

    // The interface is drawn on the basis of a 320 * 550 window, and can be scaled as a whole
    property real scaleFactor: pluginSettings.interfaceScaling
    property real topDataBlock: 40 * mainDialog.scaleFactor

    width: 320 * mainDialog.scaleFactor
    height: 550 * mainDialog.scaleFactor

    topPadding: 2 * mainDialog.scaleFactor
    leftPadding: 5 * mainDialog.scaleFactor
    rightPadding: 5 * mainDialog.scaleFactor
    bottomPadding: 2 * mainDialog.scaleFactor

    // Center on Screen
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2

    /////////// Top Bar /////////////////

    Button{
      id: settingsButton

      anchors.left: parent.left
      anchors.top: parent.top
      width: 40 * mainDialog.scaleFactor
      height: 40 * mainDialog.scaleFactor

      rightPadding: 0
      leftPadding: 0
      bottomPadding: 0
      topPadding: 0
      flat: true
      icon.source: "ic_tune_black_24dp.svg"

      onClicked: configDialog.open()
    }

    Text {
      x: 55 * mainDialog.scaleFactor
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.leftMargin: 55 * mainDialog.scaleFactor
      width: 90 * mainDialog.scaleFactor
      height: 25 * mainDialog.scaleFactor

      text: 'Head. ' + Math.round(smoothCompass.viewAngle())
      font.pixelSize: 10 * mainDialog.scaleFactor
      verticalAlignment: Text.AlignVCenter
    }

    Text {
      x: 175 * mainDialog.scaleFactor
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.leftMargin: 175 * mainDialog.scaleFactor
      width: 90 * mainDialog.scaleFactor
      height: 25 * mainDialog.scaleFactor

      text: {
        if(pluginSettings.magneticDeclination > 0){
          'Decl. ' + '+' + Math.round(pluginSettings.magneticDeclination*10)/10 + ' E'
        }else{
          'Decl. ' + Math.round(pluginSettings.magneticDeclination*10)/10 + ' W'
        }
      }
      font.pixelSize: 10 * mainDialog.scaleFactor
      verticalAlignment: Text.AlignVCenter
    }


    Rectangle {
      id: calibIndicator
      width: 25 * mainDialog.scaleFactor
      height: 25 * mainDialog.scaleFactor
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.rightMargin: 0

      color:
          if(compass.calibrationLevel > 0.95){
            "#099925"
          }
          else if(compass.calibrationLevel > 0.80){
            "#e0860a"
          }else{
            "#e00a0a"
          }
      radius: 12 * mainDialog.scaleFactor
      border.width: 0
    }

    Text {
      width: 25 * mainDialog.scaleFactor
      height: 25 * mainDialog.scaleFactor
      anchors.top: parent.top
      anchors.horizontalCenter: calibIndicator.horizontalCenter

      text: Math.round(compass.calibrationLevel*100) + '%'
      color:   "#ffffff"
      font.pixelSize: 8 * mainDialog.scaleFactor
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    /////////////  Plane properties /////////////////

    CheckBox {
      id: planeSave
      checked: true

      anchors.top: strikeValue.top
      anchors.left: parent.left
      anchors.leftMargin: 10 * mainDialog.scaleFactor
      scale: mainDialog.scaleFactor * 1.1

      text: qsTr("Plane")
    }

    /// Strike

    Text {
      visible: planeSave.checked
      id: strikeValue

      anchors.top: parent.top
      anchors.topMargin: mainDialog.topDataBlock * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 100 * mainDialog.scaleFactor

      text: 'Strike'
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 14 * mainDialog.scaleFactor
    }

    Text {
      visible: planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 15) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 100 * mainDialog.scaleFactor
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter

      text: Math.round(mainDialog.strike )
      font.pixelSize: 24 * mainDialog.scaleFactor
      font.bold: true
    }

    /// Dip dir

    Text {
      visible: planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: mainDialog.topDataBlock * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 180 * mainDialog.scaleFactor

      text: 'Dip dir.'
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 14 * mainDialog.scaleFactor
    }

    Text {
      visible: planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 15) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 180 * mainDialog.scaleFactor

      text: Math.round(mainDialog.dipDirection )
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 24 * mainDialog.scaleFactor
      font.bold: true
    }

    /// Dip

    Text {
      visible: planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: mainDialog.topDataBlock * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 260 * mainDialog.scaleFactor

      text: 'Dip'
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 14 * mainDialog.scaleFactor
    }

    Text {
      visible: planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 15) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 260 * mainDialog.scaleFactor

      text: Math.round(mainDialog.dip)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 24 * mainDialog.scaleFactor
      font.bold: true
    }

    /////////////  Line properties /////////////////

    CheckBox {
      id: lineSave
      checked: true

      anchors.top: trendValue.top
      anchors.left: parent.left
      anchors.leftMargin: 10 * mainDialog.scaleFactor
      scale: mainDialog.scaleFactor * 1.1

      text: qsTr("Line")
    }

    /// Trend

    Text {
      visible: lineSave.checked
      id: trendValue

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 50) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 100 * mainDialog.scaleFactor

      text: 'Trend'
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 14 * mainDialog.scaleFactor
    }

    Text {
      visible: lineSave.checked
      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 65) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 100 * mainDialog.scaleFactor

      text: Math.round(mainDialog.trend )
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 24 * mainDialog.scaleFactor
      font.bold: true
    }


    /// Plunge

    Text {
      visible: lineSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 50) * mainDialog.scaleFactor
      anchors.left: parent.left

      text: 'Plunge'
      anchors.leftMargin: 180 * mainDialog.scaleFactor
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 14
    }

    Text {
      visible: lineSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 65) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 180 * mainDialog.scaleFactor

      text: Math.round(mainDialog.plunge )
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 24 * mainDialog.scaleFactor
      font.bold: true
    }

    /// Pitch

    Text {
      visible: lineSave.checked && planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 50) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 260 * mainDialog.scaleFactor

      text: 'Pitch'
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 14 * mainDialog.scaleFactor
    }

    Text {
      visible: lineSave.checked && planeSave.checked

      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 65) * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 260 * mainDialog.scaleFactor

      text: Math.round(mainDialog.pitch)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.pixelSize: 24 * mainDialog.scaleFactor
      font.bold: true
    }


    ////////////////////////// Wind Rose //////////////////

    Button{
      id: windRose

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: (mainDialog.topDataBlock + 105) * mainDialog.scaleFactor
      width: 250 * mainDialog.scaleFactor
      height: 250 * mainDialog.scaleFactor

      rightPadding: 0
      leftPadding: 0
      bottomPadding: 0
      topPadding: 0

      icon.source: "windRose.svg"
      icon.height: 250 * mainDialog.scaleFactor
      icon.width: 250 * mainDialog.scaleFactor

      rotation : - mainDialog.heading

      onClicked: {
        mainDialog.isReactive = !mainDialog.isReactive
      }
    }

    Rectangle{
      id: headingMark

      width: 4 * mainDialog.scaleFactor
      height : 8 * mainDialog.scaleFactor
      anchors.horizontalCenter: windRose.horizontalCenter
      anchors.bottom: windRose.top

      color:  "black"
    }

    Rectangle{
      id: strikeBar
      visible: planeSave.checked

      height: 4 * mainDialog.scaleFactor
      width : 220 * mainDialog.scaleFactor
      anchors.horizontalCenter: windRose.horizontalCenter
      anchors.verticalCenter: windRose.verticalCenter

      rotation:  - mainDialog.heading + mainDialog.strike + 90

      color: mainDialog.isReactive ? "black": Theme.mainColor // couleur du thème ??
    }

    Rectangle{
      id: dipBar
      visible: planeSave.checked

      width: 4 * mainDialog.scaleFactor
      height : 110 * mainDialog.scaleFactor * Math.cos( mainDialog.dip * Math.PI / 180)
      anchors.horizontalCenter: windRose.horizontalCenter
      anchors.bottom: windRose.verticalCenter

      transform: Rotation { origin.x: dipBar.width / 2 ;
        origin.y: dipBar.height;
        angle: - mainDialog.heading + mainDialog.strike + 90}

      color: mainDialog.isReactive ? "black": Theme.mainColor
    }

    Shape{
      id: lineArrow
      visible: lineSave.checked

      property real shaftLength: (30 + 80  * Math.cos( mainDialog.plunge * Math.PI / 180) ) * mainDialog.scaleFactor

      width: 20 * mainDialog.scaleFactor
      height : lineArrow.shaftLength
      anchors.horizontalCenter: windRose.horizontalCenter
      anchors.bottom: windRose.verticalCenter

      transform: Rotation { origin.x: lineArrow.width / 2 ;
        origin.y: lineArrow.height;
        angle: - mainDialog.heading + mainDialog.trend}

      ShapePath{
        fillColor: mainDialog.isReactive ? "black": Theme.mainColor
        strokeWidth: 0

        startX: 10 * mainDialog.scaleFactor
        startY: 0  * mainDialog.scaleFactor
        PathLine { x: 20 * mainDialog.scaleFactor; y: 30  * mainDialog.scaleFactor}
        PathLine { x: 12 * mainDialog.scaleFactor; y: 30  * mainDialog.scaleFactor}
        PathLine { x: 12 * mainDialog.scaleFactor; y: lineArrow.shaftLength }
        PathLine { x: 8  * mainDialog.scaleFactor; y: lineArrow.shaftLength }
        PathLine { x: 8  * mainDialog.scaleFactor; y: 30  * mainDialog.scaleFactor}
        PathLine { x: 0  * mainDialog.scaleFactor; y: 30  * mainDialog.scaleFactor}
        PathLine { x: 10 * mainDialog.scaleFactor; y: 0   * mainDialog.scaleFactor}
      }
    }

    ///////////////// Placeholder when not frozen /////////////////////
    Text {
      id: tapToFreeze
      visible: mainDialog.isReactive

      anchors.bottom: parent.bottom
      anchors.bottomMargin: 50 * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 30 * mainDialog.scaleFactor

      text: 'Tap compass to freeze & save data'
      font.pixelSize: 16 * mainDialog.scaleFactor
      font.italic: true
    }


    ///////////////// Save data /////////////////////
    Text {
      id: targetText
      visible: !mainDialog.isReactive

      anchors.bottom: parent.bottom
      anchors.bottomMargin: 60 * mainDialog.scaleFactor
      anchors.left: parent.left
      anchors.leftMargin: 30 * mainDialog.scaleFactor

      text: 'Target layer:'
      font.pixelSize: 16 * mainDialog.scaleFactor
    }

    ComboBox {
      id: pointLayerCombo
      visible: !mainDialog.isReactive
      currentIndex: 0

      height: 36 * mainDialog.scaleFactor
      anchors.verticalCenter: targetText.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: 30 * mainDialog.scaleFactor

      model: pointLayerPickerModel
      textRole: "name"
      font.pixelSize: 14 * mainDialog.scaleFactor

      onActivated:{
        root.targetLayer = currentIndex
      }
    }

    QfButton {
      id: saveButton
      visible: !mainDialog.isReactive

      anchors.bottom: parent.bottom
      anchors.topMargin: 5 * mainDialog.scaleFactor
      anchors.horizontalCenter: parent.horizontalCenter
      width: 150 * mainDialog.scaleFactor
      height: 50 * mainDialog.scaleFactor

      text: "Save reading"

      onClicked: {
        if(mainDialog.isReactive){
          mainWindow.displayToast("Cannot save, freeze reading first")
        } else {
          tryAutoFill()
        }
      }
    }

    //////////// Callbacks

    onOpened: {
     // mainDialog.isReactive = true
      // saveRow.visible = false
      populatePointLayerPicker()
      pointLayerCombo.currentIndex= root.targetLayer

     // mainDialog.scaleFactor = pluginSettings.interfaceScaling

    }

    onAccepted: {

    }
  }

  function tryAutoFill() {

    // Select the layer on which we want to write
    // if the user wants to write to "active layer"
    if(root.targetLayer===0){
     // nothing special
      }else{
    // The user has selected something else
    // Preserve this layer for restoration at the end
      currentlyActiveLayer = dashBoard.activeLayer

      // Get the target layer
      var item = pointLayerPickerModel.get(root.targetLayer)
      // if (item.isHeader) { currentIndex = currentIndex > 0 ? currentIndex - 1 : 0; return }
      //pointLayerName = (currentIndex === 0) ? "" : item.name
      var layer = qgisProject.mapLayersByName(item.name )[0]
      dashBoard.activeLayer = layer
    }

    // check if we can do something with the active layer
      dashBoard.ensureEditableLayerSelected()

      // Check whether we are using a point geometry
      if (dashBoard.activeLayer.geometryType() !== Qgis.GeometryType.Point) {
        mainWindow.displayToast(qsTr('The target vector layer must be a point geometry'))
        return
      }

    // Create geometry
    //const pos = GeometryUtils.reprojectPoint(positionSource.projectedPosition, positionSource.coordinateTransformer.destinationCrs, dashBoard.activeLayer.crs);
    const pos = GeometryUtils.reprojectPoint(canvas.mapSettings.center, qgisProject.crs, dashBoard.activeLayer.crs);
    const elevation = positionSource.positionInformation.elevation;
    let wkt = '';
    switch (dashBoard.activeLayer.wkbType()) {
    case Qgis.WkbType.MultiPointZ:
      wkt = 'MULTIPOINTZ((' + pos.x + ' ' + pos.y + ' ' + elevation + '))';
      break;
    case Qgis.WkbType.MultiPointM:
      wkt = 'MULTIPOINTM((' + pos.x + ' ' + pos.y + ' 0 ))';
      break;
    case Qgis.WkbType.MultiPointZM:
      wkt = 'MULTIPOINTZM((' + pos.x + ' ' + pos.y + ' ' + elevation + ' 0))';
      break;
    case Qgis.WkbType.MultiPoint:
      wkt = 'MULTIPOINT((' + pos.x + ' ' + pos.y + '))';
      break;
    case Qgis.WkbType.PointZ:
      wkt = 'POINTZ(' + pos.x + ' ' + pos.y + ' ' + elevation + ')';
      break;
    case Qgis.WkbType.PointM:
      wkt = 'POINTM(' + pos.x + ' ' + pos.y + ' 0 )';
      break;
    case Qgis.WkbType.PointZM:
      wkt = 'POINTZM(' + pos.x + ' ' + pos.y + ' ' + elevation + ' 0)';
      break;
    case Qgis.WkbType.Point:
      wkt = 'POINT(' + pos.x + ' ' + pos.y + ')';
      break;
    default:
    }

    let geometry = GeometryUtils.createGeometryFromWkt(wkt)

    // Create a blank feature object with the right geometry
    let feature = FeatureUtils.createBlankFeature(dashBoard.activeLayer.fields, geometry)

    // Clear existing defaults etc.
    // No good because we loose even the ones we'd prefer to keep such as timedate!
    //

    // Try to populate fields
    var fieldNames = feature.fields.names

    // Geometry
    for (var i = 0; i < fieldNames.length; i++) {
      var fieldName = fieldNames[i]

      // Geometry
      // NOT WORK is geometry is defined as a value-relation in form settings
      /*if (geomFieldNames.indexOf(fieldName) !== -1) {
           if(planeSave.checked&&lineSave.checked){
                feature.setAttribute(i,"Plane with line")

            } else if(planeSave.checked){
                feature.setAttribute(i,"Plane")

            } else if(lineSave.checked){
                feature.setAttribute(i,"Line")
            }
         }*/

      // Plane
      if(planeSave.checked){
        if (dipFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.dip))
        }
        else if (dipDirectionFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.dipDirection))
        }
        else if (strikeFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.strike))
        }
      }

      // Line
      if(lineSave.checked){
        if (trendFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.trend))
        }
        else if (plungeFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.plunge))
        }
        else if (pitchFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.pitch))
        }
      }
    }


    // Transfert to the editing form
    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.featureModel.resetAttributes(true)
    overlayFeatureFormDrawer.state = 'Add'

    // Close the window, open the drawer
    mainDialog.close()
    overlayFeatureFormDrawer.open()

    // The Connection previsouly setup will ensure we restore the originally active layer

  } // end function

  QfToolButton {
    id: pluginButton
    iconSource: 'Compass_icon.svg'
    iconColor: Theme.mainColor
    bgcolor: Theme.darkGray
    round: true
    
    onClicked: {
      mainDialog.open()
    }
  }

  // Persistent settings — edited via the ⚙ button in QField's plugin manager
  Settings {
    id: pluginSettings
    category: "geologicalCompassPlugin"
    property real magneticDeclination: -1.5
    property bool southernHemisphere: false
    property real smoothingAlpha: 0.05
    property real smoothingCompAlpha: 0.02
    property real interfaceScaling: 1.0
  }

  function configure() {
    configDialog.open()
  }

  Dialog {
    id: configDialog
    parent: mainWindow.contentItem
    anchors.centerIn: parent
    visible: false
    modal: true
    title: "Geological Compass Plugin Settings"
    standardButtons: Dialog.Ok | Dialog.Cancel

    Column {
      spacing: 16
      width: 250
      topPadding: 8

      Column {
        width: parent.width
        spacing: 4
        Text {
          text: "Magnetic Declination (°)"
          font.pixelSize: 14
          font.bold: true
        }

        Text {
          text: 'Automatic detection = ' + Math.round(positionSource.positionInformation.magneticVariation*10)/10 + '°'
          font.pixelSize: 12
        }

        TextField {
          id: declinationField
          width: parent.width / 2
          inputMethodHints: Qt.ImhFormattedNumbersOnly
          placeholderText: "e.g. -1.5"
        }
      }

      Column{
        width: parent.width
        spacing: 4

        Text {
          text: "Interface size"
          font.pixelSize: 14
          font.bold: true

        }

        QfSlider{
          id: interfaceSlider
          from: 0.5
          to: 2
          value: 1.0
          stepSize: 0.1
          implicitWidth : parent.width
          implicitHeight: 10
          showValueLabel: true
        }

        Text {
          text: " "
          font.pixelSize: 12
        }

      }

      Column {
        width: parent.width
        spacing: 4
        Text {
          text: "Acc. smoothing constant"
          font.pixelSize: 14
          font.bold: true

        }
        Text {
          text: " (lower means slower adjustment)"
          font.pixelSize: 12
          font.italic: true
        }


        TextField {
          id: smoothField
          width: parent.width / 2
          inputMethodHints: Qt.ImhFormattedNumbersOnly
          placeholderText: "0.05"
        }
      }

      Column {
        width: parent.width
        spacing: 4
        Text {
          text: "Compass smoothing constant"
          font.pixelSize: 14
          font.bold: true

        }

        Text {
          text: " (lower means slower adjustment)"
          font.pixelSize: 12
          font.italic: true
        }

        TextField {
          id: smoothCompField
          width: parent.width / 2
          inputMethodHints: Qt.ImhFormattedNumbersOnly
          placeholderText: "0.02"
        }
      }

      Row {
        spacing: 12
        Text {
          text: "Inverse dip direction (legacy)" // What is going on here?
          font.pixelSize: 14
          anchors.verticalCenter: parent.verticalCenter
        }
        Switch {
          id: hemisphereSwitch
          checked: false
        }
      }

    }

    onOpened: {
      declinationField.text = pluginSettings.magneticDeclination.toString()
      hemisphereSwitch.checked = pluginSettings.southernHemisphere
      smoothField.text = pluginSettings.smoothingAlpha.toString()
      smoothCompField.text = pluginSettings.smoothingCompAlpha.toString()
      interfaceSlider.value =  pluginSettings.interfaceScaling

    }

    onAccepted: {
      var dec = parseFloat(declinationField.text)
      if (!isNaN(dec)) pluginSettings.magneticDeclination = dec
      var smooth = parseFloat(smoothField.text)
      if (!isNaN(dec)) pluginSettings.smoothingAlpha = smooth
      var smoothComp = parseFloat(smoothCompField.text)
      if (!isNaN(dec)) pluginSettings.smoothingCompAlpha = smoothComp

      pluginSettings.interfaceScaling = interfaceSlider.value

      pluginSettings.southernHemisphere = hemisphereSwitch.checked
    }
  }

}


