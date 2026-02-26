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
	vertices: {vector}
}
export type GroupShape = {
	ty: "Group",
	shapes: {Shape},
	transform: CFrame,
}
export type MeshShape = {
	ty: "Mesh",
	transform: CFrame,
	size: vector,
	mesh: MeshPart,
}
export type Shape = BoxShape | CylinderShape | SphereShape | WedgeShape | GroupShape | MeshShape
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
}
export type Zone = {
	getRandomPoint: (Zone) -> vector,
	isPointInZone: (Zone, point: vector) -> boolean,
	isBoxInZone: (Zone, cframe: CFrame, size: vector) -> boolean,
	rebuild: (Zone) -> (),
	rebuildIfDirty: (Zone) -> (),
	
	shapes: {ShapeInstance},
	bvh: Geometry.BvhNode,
	boxes: {Geometry.Box},
	bvhDirty: boolean,
}
export type TrackGroup = {
	update: (TrackGroup) -> (),
	removeFrom: (TrackGroup, listener: ZoneListener) -> (),
	addItem: (TrackGroup, item: ZoneItem) -> (),
	addItems: (TrackGroup, items: ZoneItems) -> (),
	removeItem: (TrackGroup, item: ZoneItem) -> (),
	removeItems: (TrackGroup, items: ZoneItems) -> (),
	clear: (TrackGroup) -> (),
	
	mutable: ZoneItems,
	immutable: ZoneItems,
	listeners: {ZoneListener}
}
export type ZoneListenerData = {
	partsSet: {[BasePart]: boolean},
	attachmentsSet: {[Attachment]: boolean},
	pvinstancesSet: {[PVInstance]: boolean},
	partToModel: {[BasePart]: Model},
	partToPlayer: {[BasePart]: Player},
	modelPartsInside: {[Model]: {BasePart}},
	playerPartsInside: {[Player]: {BasePart}},
	enterObservers: {(ZoneItem) -> ()},
	exitObservers: {(ZoneItem) -> ()},
	stopped: boolean,
	partConnections: {[BasePart]: {RBXScriptConnection}},
	attachmentConnections: {[Attachment]: {RBXScriptConnection}},
	pvinstanceConnections: {[PVInstance]: {RBXScriptConnection}},
	modelConnections: {[Model]: {RBXScriptConnection}},
	playerConnections: {[Player]: {RBXScriptConnection}},
}
export type ZoneListener = typeof(setmetatable({}::{
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
}, {}::{__iter: (ZoneListener) -> () -> ZoneItem}))
return nil