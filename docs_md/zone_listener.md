# ZoneListener
---

A `ZoneListener` is an object that can listen to when certain items enter the geometric boundaries of a `Zone` defined by its `ShapeInstance`s.

## Definition
---
```luau
setmetatable<{
	onEnter: (ZoneListener, fn: (item: ZoneItem) -> ()) -> Disconnector,
	onExit: (ZoneListener, fn: (item: ZoneItem) -> ()) -> Disconnector,
	observe: (ZoneListener, fn: (item: ZoneItem) -> (() -> ())?) -> Disconnector,

	setGroups: (ZoneListener, groups: {TrackGroup}) -> (),

	subscribe: (ZoneListener, zone: Zone) -> (),
	unsubscribe: (ZoneListener, zone: Zone) -> (),
	unsubscribeAll: (ZoneListener) -> (),

	precision: "Part" | "BoundingBox",
	queryShape: "Point" | "Box",
	groups: {TrackGroup},
	zones: {Zone},
	itemsInside: ZoneItems,

	iter: (ZoneListener) -> () -> ZoneItem,
	data: ZoneListenerData
}, {__iter: (ZoneListener) -> () -> ZoneItem}>
```

## Methods
---

### ZoneListener:subscribe(zone: Zone) -> ()

Subscribes this `ZoneListener` to the `Zone`, making any item this listener is tracking who enters the geometric boundaries of the `Zone` fire events.

### ZoneListener:unsubscribe(zone: Zone) -> ()

Unsubscribes this `ZoneListener` from `zone`, cleaning up any internal listeners and events in the process.

### ZoneListener:unsubscribeAll() -> ()

Unsubscribes this `ZoneListener` from all `Zone`s it's subscribed to.

### ZoneListener:onEnter(fn: (item: ZoneItem) -> ()) -> Disconnector

Connects `fn` to be called when any `ZoneItem` enters the geometric boundaries of any subscribed `Zone`

### ZoneListener:onExit(fn: (item: ZoneItem) -> ()) -> Disconnector

Connects `fn` to be called when any `ZoneItem` exits the geometric boundaries of any subscribed `Zone`

### ZoneListener:observe(fn: (item: ZoneItem) -> (() -> ())?) -> Disconnector

Connects `fn` to be called when any `ZoneItem` enters the geometric boundaries of any subscribed `Zone`, and for the returned function (if any) to be called when it exits it. 

### ZoneListener:setGroups(groups: {TrackGroup}) -> ()

Sets the `TrackGroup`s that this `ZoneListener` should be listening for.

### ZoneListener:iter() -> () -> ZoneItem

Iterates through all `ZoneItem`s that are geometrically inside the `Zone`s the `ZoneListener` is currently subscribed to.

## Fields
---

### ZoneListener.precision: "Part" | "BoundingBox"

Determines how precise the collision of `TrackGroup` items should be.

| Precision | Description |
| --- | --- |
| `"Part"` | In player items, model items, pvinstance items etc, the collision will be determined by the collision of their individual parts instead of the bounding box. So for example if a players arm extends into a zone such that the bounding box intersects it but no part actually touches it, this will not trigger an entry event. |
| `"BoundingBox"` | In player items, model items, pvinstance items etc, the collision will be determined by the collision of their respective bounding boxes instead of the parts they're composed of. This is faster but can cause false-entries such as when specific pokey parts of a model extend the bounding box of it such that the bounding box intersects your zone but no part of it actually does. |

### ZoneListener.queryShape: "Point" | "Box"

Determines what method should be used to determine if a tracked item is in a zone or not.

| Query Shape | Description |
| `"Point"` | Items will be inside the zone if their center points collide with it. |
| `"Box"` | Items will be inside the zone if their bounding box collides with it. |

### ZoneListener.itemsInside: ZoneItems

All the items geometrically inside the `Zone`s this `ZoneListener` is listening to.

### ZoneListener.groups: {TrackGroup}

`TrackGroup`s being tracked by this `ZoneListener`.

### ZoneListener.zones: {Zone}

`Zone`s this `ZoneListener` is subscribed to.