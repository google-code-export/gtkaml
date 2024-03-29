/* GtkamlSAXParser.vala
 * 
 * Copyright (C) 2008-2011 Vlad Grecescu
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with main.c; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor Boston, MA 02110-1301,  USA
 *
 * Author:
 *        Vlad Grecescu (b100dian@gmail.com)
 */
using GLib;
using Vala;

/** this is the Flying Spaghetti Monster */
public class Gtkaml.SAXParser : GLib.Object {
	/** the only reason this is public is to be accessible from the [Import]s */
	public void* xmlCtxt;
	public Vala.CodeContext context {get;private set;}
	public weak SourceFile source_file {get;private set;}
	private StateStack states {get;set;}
	private Vala.Map<string,int> generated_identifiers_counter = new HashMap<string,int> (str_hash, str_equal);
	/** prefix/vala.namespace pair */
	private Vala.Map<string,string> prefixes_namespaces {get;set;}

	private Gtkaml.RootClassDefinition root_class_definition {get;set;}	
	public string gtkaml_prefix="gtkaml";	
	
	public SAXParser( Vala.CodeContext context, Vala.SourceFile source_file) {
		this.context = context;
		this.source_file = source_file;
	}
	
	construct {
		states = new StateStack ();	
		prefixes_namespaces = new Vala.HashMap<string,string> (str_hash, str_equal, str_equal);
		root_class_definition = null;
	}
	
	public virtual RootClassDefinition parse () {
		string contents;
		ulong length;
		
		try {
			FileUtils.get_contents ( this.source_file.filename, out contents, out length);
		} catch (FileError e) {
			Report.error (null, e.message);
		}

		State initial_state = new State (StateId.SAX_PARSER_INITIAL_STATE, null);
		states.push (initial_state); 
		start_parsing (contents, length);
		return root_class_definition;
	}
	
	public extern void start_parsing (string contents, ulong length);
	
	public extern void stop_parsing();
	
	public extern int column_number();
	
	public extern int line_number();
	
	public void start_element (string localname, string? prefix, 
		 string URI, int nb_namespaces, 
		 [CCode (array_length = false, array_null_terminated = false)] 
		 string[] namespaces, 
		 int nb_attributes, int nb_defaulted, 
		 [CCode (array_length = false, array_null_terminated = false)]
		 string[] attributes)
	{
		var attrs = parse_attributes( attributes, nb_attributes );
		State state = states.peek();
		var source_reference = create_source_reference ();
		switch (state.state_id) {
		case StateId.SAX_PARSER_INITIAL_STATE:
			//Frist Tag! - that means, add "using" directives first
			var nss = parse_namespaces (namespaces, nb_namespaces);
			foreach (XmlNamespace ns in nss) {
				if ( null == ns.prefix || null != ns.prefix && ns.prefix != gtkaml_prefix)
				{
					string[] uri_definition = ns.URI.split_set(":");	
					var namespace_reference = new Vala.UsingDirective(new UnresolvedSymbol (null, "GLib", null), source_reference);
					source_file.add_using_directive (namespace_reference);
					if (null == ns.prefix) {
						//stderr.printf ("adding '%s':'%s' to prefixes_namespaces map\n", "", uri_definition[0]);
						prefixes_namespaces.set ("", uri_definition[0]); 
					} else {
						//stderr.printf ("adding '%s':'%s' to prefixes_namespaces map\n", ns.prefix, uri_definition[0]);
						prefixes_namespaces.set (ns.prefix, uri_definition[0]); 
					}
				}
			}
			
			TypeSymbol clazz = lookup_class (prefix_to_namespace (prefix), localname);
			if (clazz == null) {
				Report.error ( source_reference, "%s not a class".printf (localname));
				stop_parsing (); 
				return;
			}

			this.root_class_definition = get_root_definition (clazz, attrs, prefix);
													
			states.push (new State (StateId.SAX_PARSER_CONTAINER_STATE, root_class_definition));
			break;
		case StateId.SAX_PARSER_CONTAINER_STATE:	
			TypeSymbol clazz = lookup_class (prefix_to_namespace (prefix), localname);
			
			if (clazz != null) { //this is a member/container child object
				ClassDefinition class_definition = get_child_for_container (clazz, state.class_definition, attrs, prefix);
				states.push (new State (StateId.SAX_PARSER_CONTAINER_STATE, class_definition));
			} else { //no class with this name found, assume it's an attribute
				string fqan;
				ClassDefinition attribute_parent_class_definition = state.class_definition;
				
				if (prefix != null) 
					fqan = prefix + "." + localname;
				else 
					fqan = localname;
				if (attrs.size > 0) { //an attribute cannot have.. attributes
					Report.error (source_reference, "No class %s.%s found.".printf(prefix_to_namespace (prefix), localname));
				}
				states.push (new State (StateId.SAX_PARSER_ATTRIBUTE_STATE, attribute_parent_class_definition, null, fqan));
			}
			break;
		case StateId.SAX_PARSER_ATTRIBUTE_STATE:
			//a tag found within an attribute state switches us to container_state
			if (state.attribute != null) { //this was created by non-discardable text nodes
				Report.error (source_reference, "Incorrect attribute definition for %s".printf (state.attribute_name));
				stop_parsing ();
				return;
			}

			TypeSymbol clazz = lookup_class (prefix_to_namespace (prefix), localname);
			
			ClassDefinition attribute_value_definition;
			if (clazz != null) { //this is a member/container child object
				attribute_value_definition = get_child_for_container (clazz, null, attrs, prefix);
			} else {
				Report.error (source_reference, "No class '%s' found".printf (localname));
				stop_parsing();
				return;
			}
			ComplexAttribute attr = new ComplexAttribute (strip_attribute_hyphens (state.attribute_name), attribute_value_definition);
			state.attribute = attr;

			//add the attribute into the parent container
			state.class_definition.add_attribute (attr);		
			states.push (new State (StateId.SAX_PARSER_CONTAINER_STATE, attribute_value_definition));
			break;
		default:
			Report.error( source_reference, "Invalid Gtkaml SAX Parser state");
			stop_parsing(); 
			return;
		}
	}
	
	public void characters (string data, int len) {
		State state = states.peek ();
		string @value = data.substring (0, len);
		string stripped_value = @value.strip ();
		
		if (stripped_value != "")
			parse_attribute_content_as_text (state, value);
	}
	
	public void end_element (string localname, string? prefix, string URI) {
		State last_state = states.pop();
		//check if we were in 'attribute' state but no sub-tags or no text/cdata blocks were encountered
		if ((last_state != null)
			&& (last_state.state_id == StateId.SAX_PARSER_ATTRIBUTE_STATE)
			&& (last_state.attribute == null)
			&& (last_state.attribute_name != gtkaml_prefix+".preconstruct")
			&& (last_state.attribute_name != gtkaml_prefix+".construct")) {
				Report.error (create_source_reference (), 
					"%s is not well defined or is not an attribute of %s".printf (last_state.attribute_name, last_state.class_definition.base_full_name));
				stop_parsing ();
		}
	}
	
	public void cdata_block (string cdata, int len) {
		State state = states.peek ();
		if (state.state_id != StateId.SAX_PARSER_INITIAL_STATE){
			State previous_state = states.peek (1);
			if (previous_state.state_id == StateId.SAX_PARSER_INITIAL_STATE) {
				RootClassDefinition root_class = state.class_definition as RootClassDefinition;
				if (root_class.original_first_code_line < 0) {
					root_class.original_first_code_line = line_number ();
				}
				root_class.code.add (cdata.substring (0, len));
			} else {
				parse_attribute_content_as_text (state, cdata.substring (0, len));
			}
		} 
	}

	private void parse_attribute_content_as_text (State state, string content) {
		if (state.state_id == StateId.SAX_PARSER_ATTRIBUTE_STATE) {
			if (state.attribute_name == gtkaml_prefix+".preconstruct") {
				if (state.class_definition.preconstruct_code != null) {
					Report.error (create_source_reference (), "A preconstruct attribute already exists for %s".printf (state.class_definition.identifier));
					stop_parsing ();
					return;
				}
				state.class_definition.preconstruct_code = content;
			} else if (state.attribute_name == gtkaml_prefix+".construct") {
				if (state.class_definition.construct_code != null) {
					Report.error (create_source_reference (), "A construct attribute already exists for %s".printf (state.class_definition.identifier));
					stop_parsing ();
					return;
				}
				state.class_definition.construct_code = content;
			} else {
				if (state.attribute == null) {
					state.attribute = new SimpleAttribute (strip_attribute_hyphens (state.attribute_name), content);
					state.class_definition.add_attribute (state.attribute);
				} else {
					if (state.attribute is SimpleAttribute) {
						(state.attribute as SimpleAttribute).value += "\n" + content;
					} else {
						Report.error (create_source_reference (), "Cannot mix a complex attribute definition with simple values like this: attribute %s".printf (state.attribute.name));
						stop_parsing ();
						return;
					}
				}
			}
		} else {
			Report.error (create_source_reference (),
				"Invalid non-whitespace text found: '%s'".printf (content));
			stop_parsing ();
			return;
		}
	}
	
	private string prefix_to_namespace (string? prefix) {
		if (prefix == null)
			return prefixes_namespaces.get ("");		
		return prefixes_namespaces.get (prefix);		
	}
	
	public SourceReference create_source_reference () {
		return new SourceReference (source_file, line_number (),
			column_number (), line_number (), column_number ()); 
	}

	private Symbol? lookup (string [] segments, int current, Symbol ns){
		string current_segment = segments[current];
		Symbol? sym = ns.scope.lookup (current_segment);
		if (sym is Namespace) {
			return lookup (segments,current+1, (Namespace)sym);
		}
		if (current + 1 == segments.length ) {
			return sym;
		}
		return null;
	}
	
	private TypeSymbol? lookup_class (string? xmlNamespace, string name) {
		string [] namespaces;
		if (xmlNamespace != null) {
			namespaces = xmlNamespace.split (".");
			namespaces += name;
		} else {
			namespaces = {name};
		}
		
	    Symbol sym = lookup (namespaces,0,context.root);
		if (sym is TypeSymbol) {
			return (TypeSymbol)sym;
		}
		
		return null;
	}

	private string strip_attribute_hyphens (string attrname) {
		//see TDWTF, "The Hard Way"
		var tokens = attrname.split ("-");
		return string.joinv ("_", tokens);
	}

	public RootClassDefinition get_root_definition (TypeSymbol clazz, Vala.List<XmlAttribute> attrs, string? prefix) {
		RootClassDefinition root_class_definition = new Gtkaml.RootClassDefinition (create_source_reference (), "this", prefix_to_namespace (prefix),  clazz, DefinitionScope.PUBLIC);
		root_class_definition.prefixes_namespaces = prefixes_namespaces;
		foreach (XmlAttribute attr in attrs) {
			if (attr.prefix == null) {
				var simple_attribute = new SimpleAttribute (strip_attribute_hyphens (attr.localname), attr.value);
				root_class_definition.add_attribute (simple_attribute);
				continue;
			}
			if (attr.prefix != gtkaml_prefix) {
				Report.error (create_source_reference (),
					"'%s' is the only allowed prefix for attributes. Other attributes must be left unprefixed".printf (gtkaml_prefix));
				stop_parsing ();
			} else
			switch (attr.localname) {
			case "public":
			case "internal":
			case "name":
				if (root_class_definition.target_name != null) {
					Report.error (create_source_reference (),
						"A name for the class already exists ('%s')".printf (
						root_class_definition.target_name));
					stop_parsing ();
				}
				root_class_definition.target_name = attr.value;
				if (attr.localname == "internal")
					root_class_definition.definition_scope = DefinitionScope.INTERNAL;
				break;
			case "namespace":
				root_class_definition.target_namespace = attr.value;
				break;
			case "private":
				Report.error (create_source_reference (),
					"'private' not allowed on root tag.");
				stop_parsing ();
				break;
			case "construct":
				if (root_class_definition.construct_code != null) {
					Report.error (create_source_reference (),
						"A construct attribute already exists for the root class");
					stop_parsing ();
				}
				root_class_definition.construct_code = attr.value;
				break;
			case "preconstruct":
				if (root_class_definition.preconstruct_code != null) {
					Report.error (create_source_reference (),
						"A preconstruct attribute already exists for the root class");
					stop_parsing ();
				}
				root_class_definition.preconstruct_code = attr.value;
				break;
			case "implements":
				var implementsv = attr.value.split (",");
				for (int i = 0; implementsv[i]!=null; i++)
					implementsv[i] = implementsv[i].strip ();
				root_class_definition.implements = string.joinv (", ", implementsv);
				break;
			default:
				Report.warning (create_source_reference (),
					"Unknown gtkaml attribute '%s'.".printf (attr.localname));
				break;
			}
		}
		
		if (root_class_definition.target_name == null)
			Report.error (create_source_reference (),
				"No class name specified: use %s:name for this".printf (gtkaml_prefix));
		return root_class_definition;
	}
	
	public ClassDefinition get_child_for_container (TypeSymbol clazz,
		ClassDefinition? container_definition, Vala.List<XmlAttribute> attrs,
		string? prefix)
	{
		string reference = null;
		string identifier = null;
		string construct_code = null;
		string preconstruct_code = null;
		string property_desc = null;
		ClassDefinition parent_container = container_definition;
		DefinitionScope identifier_scope = DefinitionScope.CONSTRUCTOR;

		foreach (XmlAttribute attr in attrs) {
			if (attr.prefix!=null && attr.prefix==gtkaml_prefix) {
				if ((attr.localname=="public" || attr.localname=="private") || attr.localname=="internal" || attr.localname=="protected") {
					if (identifier!=null) {
						Report.error (create_source_reference (), "Cannot have multiple identifier names:%s".printf(attr.localname));
						stop_parsing (); 
						break;
					}
					identifier = attr.value;
					if (attr.localname == "public")
						identifier_scope = DefinitionScope.PUBLIC;
					else if (attr.localname == "internal")
						identifier_scope = DefinitionScope.INTERNAL;
					else if (attr.localname == "protected")
						identifier_scope = DefinitionScope.PROTECTED;
					else identifier_scope = DefinitionScope.PRIVATE;
				} else if (attr.localname=="property") {
					if (attr.value.strip ().has_suffix(";"))
						property_desc = attr.value;
					else
						property_desc = attr.value + ";";
				} else if (attr.localname=="existing") {
					reference = attr.value;
				} else if (attr.localname=="construct") {
						construct_code = attr.value;
				} else if (attr.localname=="preconstruct") {
					preconstruct_code = attr.value;
				} else if (attr.localname=="standalone") {
					if (attr.value == "true") {
						parent_container = null;
					} else {
						Report.error (create_source_reference (), "Invalid 'standalone' value");
						stop_parsing ();
					}
				} else {
					Report.error (create_source_reference (), "Unknown gtkaml attribute '%s'".printf (attr.localname));
					stop_parsing ();
				}
			} else if (attr.prefix != null) {
				Report.error (create_source_reference (),
					"%s is the only allowed prefix for attributes. Other attributes must be left unprefixed".printf (gtkaml_prefix));
				stop_parsing ();
			}
		}
		
		if (identifier != null && reference != null) {
			Report.error (create_source_reference (), "Cannot specify both existing and a new identifier name");
			stop_parsing ();
		}
		
		ClassDefinition class_definition=null;
		if (reference == null) {
			int counter = 0;
			if (identifier == null) {
				//generate a name for the identifier
				identifier = clazz.name.down (clazz.name.length);
				if (generated_identifiers_counter.contains (identifier)) {
					counter = generated_identifiers_counter.get (identifier);
				}
				identifier = "_%s%d".printf (identifier, counter);
				counter++;
				generated_identifiers_counter.set (clazz.name.down (clazz.name.length), counter);
			}

			class_definition = new ClassDefinition (create_source_reference (),
				identifier, prefix_to_namespace (prefix), clazz,
				identifier_scope, parent_container);
			class_definition.construct_code = construct_code;
			class_definition.preconstruct_code = preconstruct_code;
		} else {
			if (construct_code != null || preconstruct_code != null) {
				Report.error (create_source_reference (), "Cannot specify 'construct' or 'preconstruct' code for references");
				stop_parsing ();
			}
			class_definition = new ReferenceClassDefinition (create_source_reference (), reference, prefix_to_namespace (prefix), clazz, parent_container);
			/* now post-process the reference FIXME put this in code generator or something*/
			string reference_stripped = reference.strip ();
			if (reference_stripped.has_prefix ("{")) {
				if (reference_stripped.has_suffix ("}"))
					class_definition.identifier = reference_stripped.substring (1, reference_stripped.length -2 );
				else Report.error (create_source_reference (), "'existing' attribute not properly ended");
			} else class_definition.identifier = "(%s as %s)".printf (reference, class_definition.base_full_name);
		}
		class_definition.property_desc = property_desc;
		
		if (container_definition != null)
			container_definition.add_child (class_definition);
			
		foreach (XmlAttribute attr in attrs) {
			if (attr.prefix == null) {
				var simple_attribute = new SimpleAttribute (strip_attribute_hyphens (attr.localname), attr.value);
				class_definition.add_attribute (simple_attribute);
			}
		}
		return class_definition;
	}
	
	
	private Vala.List<XmlAttribute> parse_attributes ([CCode (array_length = false)] string[] attributes, int nb_attributes) {	
		string end;
		int walker = 0;
		var attribute_list = new Vala.ArrayList<XmlAttribute> ();
		for (int i = 0; i < nb_attributes; i++) {
			var attr = new XmlAttribute ();
			attr.localname = attributes[walker];
			attr.prefix = attributes[walker+1];
			attr.URI = attributes[walker+2];
			attr.value = attributes[walker+3];
			end = attributes[walker+4];
			attr.value = attr.value.substring (0, attr.value.length - end.length);
			attribute_list.add (attr);
			walker += 5;
		}
		return attribute_list;
	}

	private Vala.List<XmlNamespace> parse_namespaces ([CCode (array_length = false)] string[] namespaces, int nb_namespaces) {
		int walker = 0;
		var namespace_list = new Vala.ArrayList<XmlNamespace> ();
		for (int i = 0; i < nb_namespaces; i++) {
			var ns = new XmlNamespace ();
			ns.prefix = namespaces[walker];
			ns.URI = namespaces[walker+1];
			if (ns.URI != null && ns.URI.has_prefix ("http://gtkaml.org/")) {
				if (ns.prefix == null)
					Report.error (create_source_reference (),
						"You cannot use the gtkaml namespace as default namespace");
				gtkaml_prefix = ns.prefix;
				string version = ns.URI.substring ("http://gtkaml.org/".length,
					ns.URI.length - "http://gtkaml.org/".length);
				if (version > Config.PACKAGE_VERSION) {
					Report.warning (create_source_reference (),
						"Source file version (%s) newer than gtkaml compiler version (%s)".printf (version, Config.PACKAGE_VERSION));
				}
				if (version < "0.4") {
					Report.warning (create_source_reference (),
						"Source file version %s is old. The signal attributes are now interpreted differently,".printf (version)
						+ " you may have to remove enclosing braces or add them. If you already did this then change the xmlns:%s version too.".printf (gtkaml_prefix));
				}
			}
			namespace_list.add (ns);
			walker += 2;
		}
		return namespace_list;
	}
}
