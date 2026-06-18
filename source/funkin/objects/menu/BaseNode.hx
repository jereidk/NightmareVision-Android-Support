package funkin.objects.menu;

import flixel.group.FlxSpriteGroup;

using Lambda;

enum abstract NodeDirection(Int) to Int {
	var EAST = 0;
	var WEST = 180;
	var NORTH = 90;
	var SOUTH = -90;
	var NONE = 360;
	
	public var cos(get, never):Int;
	public var sin(get, never):Int;
	
	inline function get_cos() return (this == EAST ? 1 : (this == WEST ? -1 : 0));
	inline function get_sin() return (this == NORTH ? 1 : (this == SOUTH ? -1 : 0));
}

class BaseNode extends FlxSpriteGroup {
	public var id:String;
	public var selected:Bool = false;
	public var nodeDistance:Float = 400;
	
	public var connectorClass:Class<BaseNodeConnector> = BaseNodeConnector;
	public var connector:BaseNodeConnector = null;
	public var connectorsOnTop:Bool = false;
	
	public var parent:BaseNode = null;
	public var attachedNodes:Map<NodeDirection, BaseNode> = [
		NONE => null,
		WEST => null,
		EAST => null,
		NORTH => null,
		SOUTH => null,
	];
	
	public var attachDirection:NodeDirection = NONE;
	
	public var nodeX:Int = 0;
	public var nodeY:Int = 0;
	
	public function new(x:Float = 0, y:Float = 0, id:String = '') {
		super(x, y);
		this.id = id;
	}
	
	public function attachNode(node:BaseNode, direction:NodeDirection):BaseNode {
		if (isNodeDirectionParallel(direction, attachDirection)) {
			trace('You cant Do that');
			return this;
		}
		
		var prevNode:BaseNode = attachedNodes.get(direction);
		if (prevNode != null) {
			prevNode.removeConnector();
			prevNode.parent = null;
			prevNode.onDetach();
			
			remove(prevNode, true);
		}
		attachedNodes.set(direction, node);
		
		var directionRad:Float = direction / 180 * Math.PI;
		node.setPosition(nodeDistance * Math.cos(directionRad), -nodeDistance * Math.sin(directionRad));
		
		node.nodeX = (nodeX + direction.cos);
		node.nodeY = (nodeY - direction.sin);
		
		node.makeConnector(getNodeDirectionParallel(direction));
		node.attachDirection = direction;
		node.parent = this;
		
		add(node);
		
		node.onAttach(this);
		
		return node;
	}
	
	public function onAttach(parent:BaseNode):Void {}
	public function onDetach():Void {}
	
	public override function draw():Void { // kys
		if (parent != null) return;
		
		function drawConnectors(node:BaseNode):Void {
			if (node == null) return;
			
			node.connector?.draw();
			
			for (node in node.attachedNodes)
				drawConnectors(node);
		}
		
		function drawRest(node:BaseNode):Void {
			if (node == null) return;
			
			for (member in node) {
				if (member != null && member.exists && member.visible && member != node.connector)
					member.draw();
			}
			
			for (node in node.attachedNodes)
				drawRest(node);
		}
		
		if (connectorsOnTop) {
			drawRest(this);
			drawConnectors(this);
		} else {
			drawConnectors(this);
			drawRest(this);
		}
	}
	
	public function makeConnector(direction:NodeDirection):BaseNodeConnector {
		if (connector != null) removeConnector();
		
		connector = Type.createInstance(connectorClass, [this, direction]);
		add(connector);
		
		return connector;
	}
	
	public function removeConnector():BaseNodeConnector {
		var oldConnector:BaseNodeConnector = connector;
		remove(connector, true);
		connector = null;
		
		return oldConnector;
	}
	
	public function getNode(direction:NodeDirection):BaseNode {
		var node:BaseNode = attachedNodes.get(direction);
		
		if (node == null && isNodeDirectionParallel(direction, attachDirection))
			return parent;
		
		return node;
	}
	
	public function isAttachedTo(match:BaseNode):Bool {
		var check:BaseNode = this;
		
		while (check != null) {
			if (check == match) return true;
			
			check = check.parent;
		}
		
		return false;
	}
	
	public function forEachNode(fun:BaseNode -> Bool):Void {
		if (!fun(this)) return;
		
		for (node in attachedNodes) {
			if (node != null)
				node.forEachNode(fun);
		}
	}
	
	public static function getNodeDirectionFromString(?str:String):NodeDirection {
		return switch (StringTools.trim(str.toLowerCase())) {
			default: NONE;
			case 'west': WEST;
			case 'east': EAST;
			case 'north': NORTH;
			case 'south': SOUTH;
		}
	}
	
	public static function getNodeDirectionParallel(dir:NodeDirection):NodeDirection {
		return switch (dir) {
			default: NONE;
			case WEST: EAST;
			case EAST: WEST;
			case NORTH: SOUTH;
			case SOUTH: NORTH;
		}
	}
	
	public static function isNodeDirectionParallel(from:NodeDirection, to:NodeDirection):Bool {
		return (from == getNodeDirectionParallel(to));
	}
}

class BaseNodeConnector extends FlxSpriteGroup {
	public var parent:BaseNode;
	public var direction:NodeDirection;
	
	public function new(node:BaseNode, direction:NodeDirection) {
		super();
		this.parent = node;
		this.direction = direction;
		
		makeConnector();
	}
	
	public function makeConnector():BaseNodeConnector {
		return this;
	}
}