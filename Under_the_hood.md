# Inside the Compass plugin

The Geological Compass plugin taps into the device sensors (namely, the compass and the accelerometer) to obtain the device orientation in geographic reference (North/top). This is then displayed in a user-friendly way, and the user is offered the possibility to save the reading in a point layer.

## The problem: orientation of planes and lines

In geology, a common need is to orient geological planes (for instance, a strata or a fault) and/or lines (for instance, sliding marks on a fault plane). See for instance the [Wikipedia article](https://en.wikipedia.org/wiki/Strike_and_dip) or indeed any structural geology course. 

To fully define the orientation of a plane, two piece of information are required: (i) something to describe how strongly it *dips* (an angle, relative to horizontal) and (ii) something to describe in which *direction* it dips - or equivalently, the orientation of an horizontal line in the plane (its "*strike*"), in both case angles with the True North. Likewise, a line can be defined by a *trend* and a *plunge* (or, if the line belongs to a plane, by its [rake, or pitch](https://en.wikipedia.org/wiki/Rake_(geology))). 

## Device readings

A phone or a tablet typically has a *compass*, and an *accelerometer*. Assuming the device is held vertically, in portrait format, the compass reports the orientation of the top of the device relative to the *magnetic* North. The accelerometer reports the acceleration along the three "natural" axes of the device: Y is towards the top of the device, X towards the right and Z points out of the screen. If the device is resting on a surface, the acceleration is only related to the gravity and this allows to calculate the device orientation: for instance, a phone resting horizontaly will have G<sub>x</sub> and G<sub>y</sub> both equal to 0 and G<sub>z</sub> = 9.81 m/s<sup>2</sup>. Conversely, a vertical phone will have G<sub>x</sub> = G<sub>z</sub> = 0 and G<sub>y</sub> = 9.81 m/s<sup>2</sup>. Thus, it is possible to use this information to derive orientations, with a bit of trig:

 If phone Y-axis points toward azimuth (*az*), then:
```
      North component = gy * cos(az) + gx * cos(az + 90°)
                      = gy * cos(az) - gx * sin(az)
      East component  = gy * sin(az) + gx * cos(az + 90°)
                      = gy * sin(az) + gx * cos(az)
```

and so 
```
dipDirection = Math.atan2(g_east, g_north) * 180 / Math.PI
```

Similar considerations allow to compute the other directions of interest.

## Further considerations and complications

### Stabilizing the readings
The sensors of the device are not very precise, and so they tend to fluctuate a lot around the "true" value. It is therefore better to smooth the readings. Here this is done simply by keeping a running average, with the following approach:

```
smoothValue = (smoothingConstant * currentValue ) +
              (1 - smoothingConstant) * smoothValue
```

There is however an additional issue with azimuth (directions relative to North): clearly if the direction fluctuates around North, between N005 and N355, the correct average should be N000 and not N180! In this case this is done by smoothing the x and y component of the azimuth vector:
```
     var x_shd = Math.cos(heading * Math.PI / 180)
     var y_shd = Math.sin(heading * Math.PI / 180)
```
and recombining

```
      heading = Math.atan2(y_shd,x_shd) * 180 / Math.PI
      if(heading < 0) heading += 360
```

### Magnetic declination
The compass reports the orientation relative to *Magnetic North*. However, this can differ from the *True North* by up to 20° in some parts of the world. The difference is known as the [declination](https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml) . Notionally, your device may know about the declination (calculated from your position). However Qt (the toolbox used to build the interface) does not implement it in Android (see [this issue](https://github.com/opengisch/QField/issues/8006)). So we just make the user define it manually (through plugin settings).

## Interface

The interface is mostly made of a dialog, that shows (in real time) the device orientation. For convenience, this is depicted visually, with a wind rose that rotates to face North and a dip symbol (the conventional T-shaped bar) that follows the orientation. We add the possibility to "freeze" the compass, so that the user can for instance move the device to a more convenient place to read the nupers and, perhaps, add them to a field notebook.

## Saving data

The last part of the code allows to save data into a point layer. This comes with a couple of extra niceties.

First, user-made databases may use all sort of names for ther fields: the dip direction, for instance, may be stored under dipDirection, dipdir, direction_dip, etc. For each value we define a dictionary of possible names, that the plugin will recognize.

Second, we allow the user to decide to which layer should the reading be saved. This comes from a very common use case in my workflow: I'm taking photographs and orientation readings more or less constantly. Going to the layer tree to switch all the time gets tedious. So the plugin is such that the data is saved to my orientation layer, but the photo layer (for instance) remains selected. This means that I do not need to manually go to the layer tree and switch back and forth.

## The code

The code is on [github](https://github.com/jfmoyen/QField_qml_Geological_compass) and in rue QField plugin style, the best way to understand is to [read](http://catb.org/jargon/html/U/UTSL.html) it :-)

It includes the following items:

### Sensor connection
Both sensors are connected using a `Compass{}` and `Accelerometer{}` respectively. They are accompanied by respective "smoothers" :

```
Compass{
onReadingChanged: {
    ... 
    currentHeading = reading.azimuth
    smoothCompass.doSmooth(currentHeading)
    }
}

```
and

```
Item {
    id: smoothCompass
    property real heading: 0

    function doSmooth(){
    ....
    heading = ... 
    }
}
```

When the compass registers a new reading, it triggers the `doSmooth()` function of `smoothCompass`. This in turns updates `smoothCompass.heading`. The rest of the code never interacts with the actual sensors, but only refers to the smoothed versions.

### Conversion to geographic frame
An item `geoData` stores the data converted in real-world coordinates:

```
 Item {
    id: geoData

    property real dip: 0
    property real dipDirection: 0
    property real strike: 0
    ...

    function getOrientation(gx = smoothAccelerometer.xx,
                            gy = smoothAccelerometer.yy,
                            gz = smoothAccelerometer.zz,
                            hd = smoothCompass.heading) {
                        ...
                        dip = ...
                        dipDirection = ...
                            }
 }
```
`geoData` gets updated whenever the accelerometer reading changes:

```
Accelerometer {
    id: accelerometer
    ...
    onReadingChanged: {
            ...
            geoData.getOrientation()
    }
}
```

At that stage, the item `geoData` is thus ensured to always store the current, smoothed value of the variables of interest.

### The interface

The actual interface code is quite long, but straightforwards. There are only a few points of note:

- Freezing is effectuated through a boolean flag, `isReactive`. This allows to freeze the measurements in a rather simple way:
```
QfDialog {
    id: mainDialog
    ...

    property bool isReactive: true

    property real strike: isReactive ? geoData.strike : strike
    ...
}
```

- The interface is built using a width of 320 pixel and a height of 550 - but every value used is multiplied by a scaling factor, such that changing this factor is enough to resize the whole thing:

```
 property real scaleFactor: pluginSettings.interfaceScaling

    width: 320 * mainDialog.scaleFactor
    height: 550 * mainDialog.scaleFactor
```
- There are a couple of checkboxes controlling the display of plane and/or line attitude

```
CheckBox {
      id: planeSave
      checked: true
      ...
}

 Text {
      visible: planeSave.checked
      id: strikeValue
      ...

      text: 'Strike'
    }
```
- The shape of the T bar is controlled by the dip, and its orientation by the strike:
```
    Rectangle{
      id: strikeBar
      visible: planeSave.checked

      height: 4 * mainDialog.scaleFactor
      width : 220 * mainDialog.scaleFactor
      anchors.horizontalCenter: windRose.horizontalCenter
      anchors.verticalCenter: windRose.verticalCenter

      rotation:  - mainDialog.heading + mainDialog.strike + 90

      color: mainDialog.isReactive ? "black": Theme.mainColor
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
```
- The line arrow is built with a `Shape{}`. 

### Saving to the proper layer
This is a somewhat more tricky part of the job. We first let the user choose the target layer with a combobox. then, when a feature is saved, we do the following:
- Remember the currently active layer
- Make the target layer active
- Create the feature
- Restore the active layer

#### The combobox
The combobox uses a `ListModel` to store all the possible options. 
```
    ComboBox {
      id: pointLayerCombo
      visible: !mainDialog.isReactive
      currentIndex: 0

      model: pointLayerPickerModel

      onActivated:{
        root.targetLayer = currentIndex
      }
    }
```

The ListModel starts empty, and is populated by a function that looks through all the project layers and adds the ones with a point geometry to the list.

```
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
    ...
    for (var i = 0; i < pointLayers.length; i++)
      pointLayerPickerModel.append({ "name": pointLayers[i].name, "isHeader": false })
  }
```

#### Creating a feature

We create a feature object, fill in the relevant information and then open the attribute form to allow the user to complete the information:

Create a geometry from the coordinates of the crosshair (which may not be the actual device position - this is intended !) and make an empty point feature:

```
    const pos = GeometryUtils.reprojectPoint(canvas.mapSettings.center, qgisProject.crs, dashBoard.activeLayer.crs)
    let wkt = 'POINT(' + pos.x + ' ' + pos.y + ')'
    let geometry = GeometryUtils.createGeometryFromWkt(wkt)
    let feature = FeatureUtils.createBlankFeature(dashBoard.activeLayer.fields, geometry)

```
Populate the fields that we can. Here, we cycle through all the fields of the target layer, and if the field name matches one of the possible names for dip (`dipFieldNames`) we write the dip value there:

```  
    property var dipFieldNames: ["dip", "dip_angle", "pendage", "dip_ref", "P_dip", "Dip"]
    ...
    var fieldNames = feature.fields.names
     for (var i = 0; i < fieldNames.length; i++) {
      var fieldName = fieldNames[i]
         if(planeSave.checked){
        if (dipFieldNames.indexOf(fieldName) !== -1) {
          feature.setAttribute(i, Math.round(mainDialog.dip))
            }
        }
    // etc
      }
```
Finally, we transfer the feature to the feature form, and let the form logic take over from there:

```
    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.featureModel.resetAttributes(true)
    overlayFeatureFormDrawer.state = 'Add'

    // Close the window, open the drawer
    mainDialog.close()
    overlayFeatureFormDrawer.open()
```

#### Juggling with layers

The last bit is the logic to deselect/reselect the target layer. The issue here is has to do with the timing of events [(see details here)](https://community.qfield.org/t/restore-previously-selected-layer-after-closing-form/1937). So we must find a way to switch back to original layer *after* the interaction with the form drawer is completed. We do this with a Connection:

```
  Connections {
    target: overlayFeatureFormDrawer

    function onClosed() {
      dashBoard.activeLayer = currentlyActiveLayer
    }
  }
```

The rest is quite simple:

```
if(the user wants to write to a layer other than currently active){
          currentlyActiveLayer = dashBoard.activeLayer
          var item = pointLayerPickerModel.get(root.targetLayer)
          var layer = qgisProject.mapLayersByName(item.name )[0]
          dashBoard.activeLayer = layer
}
```

the `Connection()` will then take care of the rest and restore the layer upon closing the form drawer.

