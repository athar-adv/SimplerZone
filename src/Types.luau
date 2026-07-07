--SimpleZone2.types
local Geometry = require("./Geometry")
export type BoxShape = {
	ty: "Box",
	transform: CFrame,
	size: vector,
}
export type CylinderShape = {
	ty: "Cylinder",
	center: vector,
	axis: vector,
	radius: number,
	transform: CFrame,
	size: vector,
}
export type SphereShape = {
	ty: "Sphere",
	center: vector,
	radius: number,
}
export type WedgeShape = {
	ty: "Wedge",
	transform: CFrame,
	size: vector,
}
export type GroupShape = {
	ty: "Group",
	shapes: {FiniteShape},
	transform: CFrame,
}
export type MeshShape = {
	ty: "Mesh",
	transform: CFrame,
	size: vector,
	mesh: MeshPart,
}
export type BoundsShape = {
	ty: "Bounds",
	transform: CFrame,

	min: Vector3,
	max: Vector3,
}
export type CapsuleShape = {
	ty: "Capsule",
	transform: CFrame,
	size: vector,
}
export type InfiniteShape = BoundsShape
export type FiniteShape = BoxShape | CylinderShape | SphereShape | WedgeShape | GroupShape | MeshShape | CapsuleShape
export type Shape = InfiniteShape | FiniteShape

export type Disconnector = () -> ()
export type ZoneItems = {
	parts: {BasePart},
	models: {Model},
	players: {Player},
	attachments: {Attachment},
	pvinstances: {PVInstance},
}
export type ZoneItem = {
	part: BasePart?,
	model: Model?,
	player: Player?,
	attachment: Attachment?,
	pvinstance: PVInstance?,
}
export type ShapeInstance = {
	toParts: (ShapeInstance, overrideCFrame: CFrame?) -> {BasePart},
	syncWithPart: (ShapeInstance, part: BasePart) -> Disconnector,
	syncWithAttachment: (ShapeInstance, attachment: Attachment) -> Disconnector,
	attach: (ShapeInstance, zone: Zone) -> (),
	detach: (ShapeInstance, zone: Zone) -> (),
	detachAll: (ShapeInstance) -> (),

	cframe: CFrame,
	scale: vector,
	zones: {Zone},
	shape: Shape,
	metadata: {[string]: any}
}
export type Zone = {
	getRandomPoint: (Zone, bias: vector?) -> vector,

	getShapeWithPoint: (Zone, point: vector) -> ShapeInstance?,
	getShapeWithBox: (Zone, cframe: CFrame, size: vector) -> ShapeInstance?,

	isPointInZone: (Zone, point: vector) -> boolean,
	isBoxInZone: (Zone, cframe: CFrame, size: vector) -> boolean,

	rebuild: (Zone) -> (),
	rebuildIfDirty: (Zone) -> (),
	
	cleanup: (Zone) -> (),

	bvhRestructureWeight: number,

	shapes: {ShapeInstance},
	bvh: Geometry.BvhNode,
	listeners: {ZoneListener},
	boxes: {Geometry.Box},
	bvhDirty: boolean,
	metadata: {[string]: any}
}
type optionalzoneitems = {
	parts: {BasePart}?,
	models: {Model}?,
	players: {Player}?,
	attachments: {Attachment}?,
	pvinstances: {PVInstance}?,
}
export type TrackGroup = {
	update: (TrackGroup) -> (),
	removeFrom: (TrackGroup, listener: ZoneListener) -> (),
	addItem: (TrackGroup, item: ZoneItem) -> (),
	addItems: (TrackGroup, items: optionalzoneitems) -> (),
	removeItem: (TrackGroup, item: ZoneItem) -> (),
	removeItems: (TrackGroup, items: optionalzoneitems) -> (),
	clear: (TrackGroup) -> (),

	mutable: ZoneItems,
	immutable: ZoneItems,
	listeners: {ZoneListener}
}
type ZoneCallbackItem = (ZoneItem & {shape: nil, zone: nil}) | (ZoneItem & {shape: ShapeInstance, zone: Zone})

export type ZoneListenerData = {
	partsSet: {[BasePart]: boolean},
	attachmentsSet: {[Attachment]: boolean},
	pvinstancesSet: {[PVInstance]: boolean},
	partToModel: {[BasePart]: Model},
	partToPlayer: {[BasePart]: Player},
	modelPartsInside: {[Model]: {BasePart}},
	playerPartsInside: {[Player]: {BasePart}},
	enterObservers: {(ZoneCallbackItem) -> ()},
	exitObservers: {(ZoneCallbackItem) -> ()},
	-- Keyed by TrackGroup; each list is fired when an item from that group enters/exits.
	groupEnterObservers: {[any]: {(ZoneCallbackItem) -> ()}},
	groupExitObservers:  {[any]: {(ZoneCallbackItem) -> ()}},
	stopped: boolean,
	partConnections: {[BasePart]: {RBXScriptConnection}},
	attachmentConnections: {[Attachment]: {RBXScriptConnection}},
	pvinstanceConnections: {[PVInstance]: {RBXScriptConnection}},
	modelConnections: {[Model]: {RBXScriptConnection}},
	playerConnections: {[Player]: {RBXScriptConnection}},
	itemToZoneAndShape: {[any]: {shape: ShapeInstance, zone: Zone}}
}
export type ZoneListener = typeof(setmetatable({}::{
	onEnter: (ZoneListener, fn: (item: ZoneCallbackItem) -> ()) -> Disconnector,
	onExit: (ZoneListener, fn: (item: ZoneCallbackItem) -> ()) -> Disconnector,
	observe: (ZoneListener, fn: (item: ZoneCallbackItem) -> (() -> ())?) -> Disconnector,
	
	observeGroups: (ZoneListener, groups: {TrackGroup}, fn: (item: ZoneCallbackItem) -> (() -> ())?) -> Disconnector,
	onGroupItemsEnter: (ZoneListener, groups: {TrackGroup}, fn: (item: ZoneCallbackItem) -> ()) -> Disconnector,
	onGroupItemsExit:  (ZoneListener, groups: {TrackGroup}, fn: (item: ZoneCallbackItem) -> ()) -> Disconnector,

	setGroups: (ZoneListener, groups: {TrackGroup}) -> (),

	subscribe: (ZoneListener, zone: Zone) -> (),
	unsubscribe: (ZoneListener, zone: Zone) -> (),
	unsubscribeAll: (ZoneListener) -> (),
	
	cleanup: (ZoneListener) -> (),

	precision: "Part" | "BoundingBox",
	queryShape: "Point" | "Box",
	groups: {TrackGroup},
	zones: {Zone},
	itemsInside: ZoneItems,

	iter: (ZoneListener) -> () -> ZoneCallbackItem,
	data: ZoneListenerData
}, {}::{__iter: (ZoneListener) -> () -> ZoneCallbackItem}))
return nil