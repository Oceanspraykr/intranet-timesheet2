# /packages/intranet-timesheet2/www/hours/new.tcl
#
# Copyright (C) 1998-2004 various parties
# The code is based on ArsDigita ACS 3.4
#
# This program is free software. You can redistribute it
# and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation;
# either version 2 of the License, or (at your option)
# any later version. This program is distributed in the
# hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

ad_page_contract {
    Displays form to let user enter hours
    In weekly view, week would start with julian_date which is usually a Sunday or Monday   

    @param project_id
    @param julian_date 
    @param return_url 

    @author mbryzek@arsdigita.com
    @author frank.bergmann@project-open.com
    @author klaus.hofeditz@project-open.com

    @creation-date Jan 2006
} {
    { project_id 0 }
    { julian_date "" }
    { gregorian_date "" }
    { return_url "" }
    { show_week_p 1 }
    { user_id_from_search "" }
    { search_task ""}
}

# ---------------------------------------------------------
# Default & Security
# ---------------------------------------------------------

set show_context_help_p 1
# Should we show debugging information for each project?
set debug 0
set current_user_id [ad_maybe_redirect_for_registration]
set add_hours_p [im_permission $current_user_id "add_hours"]
set add_hours_all_p [im_permission $current_user_id "add_hours_all"]
set add_hours_direct_reports_p [im_permission $current_user_id "add_hours_direct_reports"]

if {!$add_hours_p} {
    ad_return_complaint 1 [lang::message::lookup "" intranet-timesheet2.Not_allowed_to_log_hours "You are not allowed to log hours."]
    ad_script_abort
}


# Is the user allowed to log hours for another user?
if {"" == $user_id_from_search } { 
    if {!$add_hours_all_p} {
	if {$add_hours_direct_reports_p} {
	    set reportees [im_user_direct_reports_ids -user_id $current_user_id]
	    if {[lsearch $reportees $user_id_from_search] < 0} {
		# User not in reportees - reset to current user
		set user_id_from_search $current_user_id 
	    }
	}
    }
}
if {"" == $user_id_from_search } { set user_id_from_search $current_user_id }
set user_name_from_search [db_string uname "select im_name_from_user_id(:user_id_from_search)"]

# ToDo: What if the user_id_from_search is already set???

set tr_class(0) " class='roweven @@visibility-class@@'"
set tr_class(1) " class='rowodd @@visibility-class@@'"

if {"" == $show_week_p} { set show_week_p 0 }
if {"" == $project_id} { set project_id 0 }
im_security_alert_check_integer -location "/intranet-timesheet2/www/hours/new" -value $project_id

# Get the date. Accept a gregorian or julian format. Use today as default.
if {![empty_string_p $gregorian_date]} { set julian_date [db_string sysdate_as_julian "select to_char(:gregorian_date::date, 'J')"] }
if {[empty_string_p $julian_date]} { set julian_date [db_string sysdate_as_julian "select to_char(sysdate,'J') from dual"] }

if {"" == $return_url} { set return_url [export_vars -base "/intranet-timesheet2/hours/index" {julian_date user_id_from_search}] }

# Check if user is allowed to log hours for this day
set weekly_logging_days [parameter::get_from_package_key -package_key intranet-timesheet2 -parameter TimesheetWeeklyLoggingDays -default "0 1 2 3 4 5 6"]

# PG to_start starts with Sunday - index (1)
if { !$show_week_p && [string first [expr [db_string dow "select to_char(to_date(:julian_date, 'J'), 'D')"] -1] $weekly_logging_days] == -1} {
    ad_return_complaint 1  [lang::message::lookup "" intranet-timesheet2.Not_Allowed "You are not allowed to log hours for this day due to configuration restrictions. (Parameter: 'TimesheetWeeklyLoggingDays') "]
}

# Should we show all the tasks of a project if the user has chosen this project specificly?
# I believe this was used in the past for a single customer...
set show_all_tasks_for_specific_project_p [parameter::get_from_package_key -package_key intranet-timesheet2 -parameter ShowAllTasksForSpecificProjectP -default "0"]

# To store fold-in/fold-out info 
set page_url "/intranet-timesheet2/hours/new"

# Get stored collapse information 
set collapse_sql "select object_id, open_p from im_biz_object_tree_status where user_id = :user_id_from_search and page_url = :page_url"
db_foreach collapse $collapse_sql {set collapsed_hash($object_id) $open_p }

# Check if WF package is installed
set workflow_installed_p [util_memoize [list db_string timesheet_wf "select count(*) from apm_enabled_package_versions where package_key = 'intranet-timesheet2-workflow'"]]

# Should entry form show or hide elements?
set default_is_fold_in_p [parameter::get -package_id [apm_package_id_from_key intranet-timesheet2] -parameter "EntryFormDefaultIsFoldIn" -default 0]

# ---------------------------------------------------------
# Calculate the start and end of the week.
# ---------------------------------------------------------

set julian_week_start $julian_date
set julian_week_end $julian_date
set h_day_in_dayweek "h.day::date = to_date(:julian_date, 'J')"

if {$show_week_p} {
    # Find Sunday (=American week start) and Saturday (=American week end)
    # for the current week by adding or subtracting days depending on the weekday (to_char(.., 'D'))

    ## set day_of_week [db_string dow "select to_char(to_date(:julian_date, 'J'), 'D')"]
    # set julian_week_start [expr $julian_date + 1 - $day_of_week]
    # set julian_week_end [expr $julian_date + (7-$day_of_week)]

    ## Reset the day to the start of the week.
    # set julian_date $julian_week_start

    # 1st day shown should be julian_date passed to this page
    set julian_week_start $julian_date
    set julian_week_end [expr $julian_date + [expr [llength $weekly_logging_days]-1]]

    # Condition to check for hours this week:
    set h_day_in_dayweek "h.day between to_date(:julian_week_start, 'J') and to_date(:julian_week_end, 'J')"
}


# Materials
set materials_p [parameter::get_from_package_key -package_key intranet-timesheet2 -parameter HourLoggingWithMaterialsP -default 0]
set material_options [im_material_options -include_empty 1 -restrict_to_uom_id [im_uom_hour]]
set default_material_id [im_material_default_material_id]

# Project_ID and list of project IDs
set project_id_for_default [lindex $project_id 0]
if {0 == $project_id} { set project_id_for_default ""}

# "Log hours for a different day"
set different_date_url [export_vars -base "index" {user_id_from_search julian_date show_week_p project_id}]

# Should we show an "internal" text comment
# in addition to the normal "external" comment?
set internal_note_exists_p [parameter::get_from_package_key -package_key intranet-timesheet2 -parameter HourLoggingInternalCommentP -default 0]
if {![im_column_exists im_hours internal_note]} {
    ad_return_complaint 1 "Internal error in intranet-timesheet2:<br>
	The field im_hours.internal_note is missing.<br>
	Please notify your system administrator to upgrade
	your system to the latest version.<br>
    "
    ad_script_abort
}
set external_comment_size 40
set internal_comment_size 0
if {$internal_note_exists_p} { 
    set external_comment_size 20
    set internal_comment_size 20
}


# Append user-defined menus
set bind_vars [list user_id $current_user_id user_id_from_search $user_id_from_search julian_date $julian_date return_url $return_url show_week_p $show_week_p]
set menu_links_html [im_menu_ul_list -no_uls 1 "timesheet_hours_new_admin" $bind_vars]

set different_project_url "other-projects?[export_url_vars julian_date user_id_from_search]"

# Log Absences
set add_absences_p [im_permission $current_user_id add_absences]
set absences_url [export_vars -base "/intranet-timesheet2/absences/new" {return_url user_id_from_search}]
set absences_link_text [lang::message::lookup "" intranet-timesheet2.Log_Absences "Log Absences"]


db_1row user_name_and_date "
select 
	im_name_from_user_id(user_id) as user_name,
	to_char(to_date(:julian_date, 'J'), 'fmDay fmMonth fmDD, YYYY') as pretty_date
from	users
where	user_id = :user_id_from_search" 


# ---------------------------------------------------------
# Calculate the <- -> buttons at the top of the timesheet page.
# ---------------------------------------------------------

set left_gif [im_gif arrow_comp_left]
set right_gif [im_gif arrow_comp_right]

if {$show_week_p} {

    set page_title [lang::message::lookup "" intranet-timesheet2.The_week_for_user "The week for %user_name_from_search%"]

    set prev_week_julian_date [expr $julian_date - 7]
    set prev_week_url [export_vars -base "new" {{julian_date $prev_week_julian_date} user_id_from_search return_url project_id show_week_p}]
    set prev_week_link "<a href=$prev_week_url>$left_gif</a>"

    set next_week_julian_date [expr $julian_date + 7]
    set next_week_url [export_vars -base "new" {{julian_date $next_week_julian_date} user_id_from_search return_url project_id show_week_p}]
    set next_week_link "<a href=$next_week_url>$right_gif</a>"

    set forward_backward_buttons "
	<tr>
	<td align=left>$prev_week_link</td>
	<td colspan=6>&nbsp;</td>
	<td align=right>$next_week_link</td>
	</tr>
    "

} else {

    set page_title "[lang::message::lookup "" intranet-timesheet2.Date_for_user "%pretty_date% for %user_name_from_search%"]"

    set prev_day_julian_date [expr $julian_date - 1]
    set prev_day_url [export_vars -base "new" {{julian_date $prev_day_julian_date} user_id_from_search project_id show_week_p}]
    set prev_day_link "<a href=$prev_day_url>$left_gif</a>"

    set next_day_julian_date [expr $julian_date + 1]
    set next_day_url [export_vars -base "new" {{julian_date $next_day_julian_date} user_id_from_search project_id show_week_p}]
    set next_day_link "<a href=$next_day_url>$right_gif</a>"

    set forward_backward_buttons "
	<tr>
	<td align=left>$prev_day_link</td>
	<td colspan=[expr 1+$internal_note_exists_p]>&nbsp;</td>
	<td align=right>$next_day_link</td>
	</tr>
    "

}

set context_bar [im_context_bar [list index "[_ intranet-timesheet2.Hours]"] "[_ intranet-timesheet2.Add_hours]"]

set log_hours_on_potential_project_p [parameter::get_from_package_key -package_key intranet-timesheet2 -parameter TimesheetLogHoursOnPotentialProjectsP -default 1]

set list_sort_order [parameter::get_from_package_key -package_key "intranet-timesheet2" -parameter TimesheetAddHoursSortOrder -default "order"]

set show_project_nr_p [parameter::get_from_package_key -package_key "intranet-core" -parameter ShowProjectNrAndProjectNameP -default 0]

# Should we allow users to log hours on a parent project, even though it has children?
set log_hours_on_parent_with_children_p [parameter::get_from_package_key -package_key "intranet-timesheet2" -parameter LogHoursOnParentWithChildrenP -default 1]

# "Solitary" projects are main projects without children.
# Some companies want to avoid logging on such projects.
set log_hours_on_solitary_projects_p [parameter::get_from_package_key -package_key "intranet-timesheet2" -parameter LogHoursOnSolitaryProjectsP -default 1]
# set log_hours_on_solitary_projects_p 0


# Determine how to show the tasks of projects. There are several options:
#	- main_project: The main project determines the subproject/task visibility space
#	- sub_project: Each (sub-) project determines the visibility of its tasks
#	- task: Each task has its own space - the user needs to be member of all tasks to log hours.
# Fix #1835325 from Koen van Winckel
set task_visibility_scope [parameter::get_from_package_key -package_key "intranet-timesheet2" -parameter TimesheetTaskVisibilityScope -default "sub_project"]

# Can the current user log hours for other users?
set add_hours_all_p [im_permission $current_user_id "add_hours_all"]

# What is a closed status?
set closed_stati_select "select * from im_sub_categories([im_project_status_closed])"
if {!$log_hours_on_potential_project_p} {
    append closed_stati_select " UNION select * from im_sub_categories([im_project_status_potential])"
}

# Determine all the members of the "closed" super-status
set closed_stati [db_list closed_stati $closed_stati_select]
set closed_stati_list [join $closed_stati ","]

# ---------------------------------------------------------
# Select the list of days for the weekly view
# ---------------------------------------------------------

# Only show day '0' if we log for a single day
if {!$show_week_p} { set weekly_logging_days [list 0] }

# ---------------------------------------------------------
# Logic to check if the user is allowed to log hours
# ---------------------------------------------------------

set edit_hours_p "t"

# When should we consider the last month to be closed?
set last_month_closing_day [parameter::get_from_package_key -package_key intranet-timesheet2 -parameter TimesheetLastMonthClosingDay -default 0]

if {0 != $last_month_closing_day && "" != $last_month_closing_day } {
    # Check that $julian_date is before the Nth of the next month:
    # Select the 1st day of the last month:
    set first_of_last_month [db_string last_month "
	select to_char(now()::date - :last_month_closing_day::integer + '0 Month'::interval, 'YYYY-MM-01')
    "]
    set edit_hours_p [db_string e "select to_date(:julian_date, 'J') >= :first_of_last_month::date"]
}

set edit_hours_closed_message [lang::message::lookup "" intranet-timesheet2.Logging_hours_has_been_closed "Logging hours for this date has already been closed. <br>Please contact your supervisor or the HR department."]


# ---------------------------------------------------------
# Build the SQL Subquery, determining the (parent)
# projects to be displayed 
# ---------------------------------------------------------

set main_project_id_list [list 0]
set main_project_id 0

if {[string is integer $project_id] && 0 != $project_id} {

    set main_project_id [db_string main_p "
	select	main_p.project_id
	from	im_projects p,
		im_projects main_p
	where	p.project_id = :project_id and
		tree_ancestor_key(p.tree_sortkey, 1) = main_p.tree_sortkey
    " -default 0]

    set parent_project_sql "
			select	:main_project_id::integer
    \t\t"

    # Project specified => only one project
    set one_project_only_p 1

    # Make sure the user can see everything below the single main project
    if {$show_all_tasks_for_specific_project_p} {
	set task_visibility_scope "specified"
    }

} elseif {[llength $project_id] > 1} {

    set main_project_id_list [db_list main_ps "
	select distinct
		main_p.project_id
	from	im_projects p,
		im_projects main_p
	where	p.project_id in ([join $project_id ","]) and
		tree_ancestor_key(p.tree_sortkey, 1) = main_p.tree_sortkey
    "]

    set parent_project_sql "
			select	p.project_id
			from	im_projects p
			where	p.project_id in ([join $main_project_id_list ","])
    \t\t"

    # An entire list of project has been selected
    set one_project_only_p 0

    # Make sure the user can see everything below the single main project
    if {$show_all_tasks_for_specific_project_p} {
	set task_visibility_scope "specified"
    }

} else {

    # Project_id unknown => select all projects
    set one_project_only_p 0

    set parent_project_sql "
	select	p.project_id
	from	im_projects p
	where 
		p.parent_id is null
		and p.project_id in (
				select	r.object_id_one
				from	acs_rels r
				where	r.object_id_two = :user_id_from_search
			    UNION
				select	project_id
				from	im_hours h
				where	h.user_id = :user_id_from_search
					and $h_day_in_dayweek
		)
		and p.project_status_id not in ($closed_stati_list)
		and p.project_type_id not in ([im_project_type_task], [im_project_type_ticket])
    "
}




# We need to show the hours of already logged projects.
# So we need to add the parents of these sub-projects to parent_project_sql.
append parent_project_sql "
    UNION
	-- Always show the main-projects of projects with logged hours
	select	main_p.project_id
	from	im_hours h,
		im_projects p,
		im_projects main_p
	where	h.user_id = :user_id_from_search
		and $h_day_in_dayweek
		and h.project_id = p.project_id
		and tree_ancestor_key(p.tree_sortkey, 1) = main_p.tree_sortkey
"



# Determine how to show the tasks of projects.
switch $task_visibility_scope {
    "main_project" {
	# main_project: The main project determines the subproject/task visibility space
	set children_sql "
				select	sub.project_id
				from	acs_rels r,
					im_projects main,
					im_projects sub
				where	r.object_id_two = :user_id_from_search
					and r.object_id_one = main.project_id
					and main.tree_sortkey = tree_ancestor_key(sub.tree_sortkey, 1)
					and main.project_status_id not in ($closed_stati_list)
					and sub.project_status_id not in ($closed_stati_list)
	"
    }
    "specified" {
	# specified: We've got an explicit "project_id"
	# Show everything that's below, even if the user isn't a member.
	set children_sql "
				select	sub.project_id
				from	im_projects main,
					im_projects sub
				where	(	main.project_id = :main_project_id 
						OR main.project_id in ([join $main_project_id_list ","])
					)
					and main.project_status_id not in ($closed_stati_list)
					and sub.tree_sortkey between
						main.tree_sortkey and
						tree_right(main.tree_sortkey)
	"

    }
    "sub_project" {
	# sub_project: Each (sub-) project determines the visibility of its tasks.
	# So we are looking for the "lowest" in the project hierarchy subproject
	# that's just above its tasks and controls the visibility of the tasks.
	# There are four conditions to determine the list of the "controlling" projects efficiently:
	#	- the controlling_project is a project
	#	- the task directly below the ctrl_project is a task.
	#	- the current user is member of the controlling project
	#	- the controlling_project is below the visible main projects 
	#	  (optional, may speedup query, but does not in general when all projects are selected)
	#
	# This query is slightly too permissive, because a single task associated with a main project
	# would make the main project the "controlling" project and show _all_ tasks in all subprojects,
	# even if the user doesn't have permissions for those. However, this can be fixed on the TCL level.
	set ctrl_projects_sql "
		select	distinct ctrl.project_id
		from	im_projects ctrl,
			im_projects task,
			acs_rels r
		where	
			task.parent_id = ctrl.project_id
			and ctrl.project_type_id not in ( [im_project_type_task], [im_project_type_ticket])
			and task.project_type_id in ( [im_project_type_task], [im_project_type_ticket] )
			and ctrl.project_status_id not in ($closed_stati_list)
			and task.project_status_id not in ($closed_stati_list)
			and r.object_id_one = ctrl.project_id
			and r.object_id_two = :user_id_from_search
	"

	set children_sql "
				-- Select any subprojects of control projects
				select	sub.project_id
				from	im_projects main,
					($ctrl_projects_sql) ctrl,
					im_projects sub
				where	ctrl.project_id = main.project_id
					and main.project_status_id not in ($closed_stati_list)
					and sub.project_status_id not in ($closed_stati_list)
					and sub.tree_sortkey between
						main.tree_sortkey and
						tree_right(main.tree_sortkey)
			UNION
				-- Select any project or task with explicit membership
				select  r.object_id_one
				from    acs_rels r
				where   r.object_id_two = :user_id_from_search
	"
    }
    "task" {
	# task: Each task has its own space - the user needs to be member of all tasks to log hours.
	set children_sql "
				-- Show sub-project/tasks only with direct membership
				select	r.object_id_one
				from	acs_rels r
				where	r.object_id_two = :user_id_from_search
	"
    }
}


set child_project_sql "
				$children_sql
			    UNION
				-- Always show projects and tasks where user has logged hours
				select	project_id
				from	im_hours h
				where	h.user_id = :user_id_from_search
					and $h_day_in_dayweek
			    UNION
				-- Project with hours on it plus any of its superiors
				select	main_p.project_id
				from	im_hours h,
					im_projects p,
					im_projects main_p
				where	h.user_id = :user_id_from_search
					and $h_day_in_dayweek
					and h.project_id = p.project_id
					and p.tree_sortkey between
						main_p.tree_sortkey and
						tree_right(main_p.tree_sortkey)
			    UNION
				-- Always show the main project itself (it showing a single project, 0 otherwise)
				select	project_id from im_projects where project_id in ([join $project_id ","])
"

# ---------------------------------------------------------
# Build the main hierarchical SQL
# ---------------------------------------------------------

# The SQL is composed of the following elements:
#
# - The "parent" project, which contains the tree_sortkey information
#   that is necessary to determine its children.
#
# - The "children" project, which represents sub-projects
#   of "parent" of any depth.
#

set sort_integer 0
set sort_legacy  0
switch $list_sort_order {
    name { 
	set sort_order "lower(children.project_name)"
    }
    order { 
	set sort_order "children.sort_order"
	set sort_integer 1
    }
    legacy {
	set sort_order "children.tree_sortkey"
	set sort_legacy 1
    }
    default { 
	set sort_order "lower(children.project_nr)"
    }
}

set exclude_closed_tickets_sql ""
if {[db_table_exists im_tickets]} { 
    set exclude_closed_tickets_sql "
		and coalesce(
			(select ticket_status_id from im_tickets t where t.ticket_id = children.project_id),
			0
		) not in (
			select * from im_sub_categories([im_ticket_status_closed])
		)
    "
}

set sql "
	select
		parent.project_id as top_project_id,
		parent.parent_id as top_parent_id,
		parent.project_name as top_parent_project_name,
		children.parent_id as parent_id,
		children.project_id as project_id,
		children.project_nr as project_nr,
		children.project_name as project_name,
		children.project_status_id as project_status_id,
		children.project_type_id as project_type_id,
		im_category_from_id(children.project_status_id) as project_status,
		parent.project_id as parent_project_id,
		parent.project_nr as parent_project_nr,
		parent.project_name as parent_project_name,
		tree_level(children.tree_sortkey) -1 as subproject_level,
		substring(parent.tree_sortkey from 17) as parent_tree_sortkey,
		substring(children.tree_sortkey from 17) as child_tree_sortkey,
		$sort_order as sort_order
	from
		im_projects parent,
		im_projects children
	where
		parent.parent_id is null
		and children.tree_sortkey between 
			parent.tree_sortkey and 
			tree_right(parent.tree_sortkey)
		and parent.project_id in ($parent_project_sql)
		and children.project_id in ($child_project_sql)
		$exclude_closed_tickets_sql
	order by
		lower(parent.project_name),
		children.tree_sortkey
"


# ---------------------------------------------------------
# Select out the hours for the different projects and dates
#
# Effectively, we are replacing here an SQL join with a join
# over a TCL hash array. This simplifies the SQL and the TCL
# logic later.
# Also, there is a "LEFT OUTER" join logic, because we need
# to show the projects even if there are no hours available
# for them at that moment.
# ---------------------------------------------------------

set material_sql "
		,coalesce(h.material_id, :default_material_id) as material_id,
		(select material_name from im_materials m where m.material_id = h.material_id) as material
"
if {!$materials_p} { set material_sql "" }


# ---------------------------------------------------------
# Check if the specified hours are already included in a
# timesheet invoices. In such a case we can't modify them
# anymore.
# ---------------------------------------------------------

if { $workflow_installed_p } { 
    set conf_status_sql "(select conf_status_id from im_timesheet_conf_objects where conf_id = h.conf_object_id) as conf_status_id," 
} else {
    set conf_status_sql "null as conf_status_id,"
}

set hours_sql "
	select
		h.*,
		to_char(h.day, 'J') as julian_day,
		$conf_status_sql
		p.project_id
		$material_sql
	from
		im_hours h,
		im_projects p
	where
		h.project_id = p.project_id and
		h.user_id = :user_id_from_search and
		$h_day_in_dayweek
"
db_foreach hours_hash $hours_sql {
    set key "$project_id-$julian_day"
    set hours_hours($key) $hours
    set hours_conf_status_id($key) $conf_status_id
    set hours_note($key) $note
    set hours_internal_note($key) $internal_note
    if {"" != $invoice_id} {
	set hours_invoice_hash($key) $invoice_id
    }
    if {$materials_p} {
	set hours_material_id($key) $material_id
	set hours_material($key) $material
    }
}

# ---------------------------------------------------------
# Get the list of open projects with direct membership
# Task are all considered open
# ---------------------------------------------------------

array set member_projects_hash {}

set open_projects_sql "
	-- all open projects with direct membership
	select	p.project_id as open_project_id
	from	im_projects p,
		acs_rels r
	where	r.object_id_two = :user_id_from_search
		and r.object_id_one = p.project_id
    UNION
	-- all open projects and super-project where the user has logged hours.
	select	main_p.project_id as open_project_id
	from	im_hours h,
		im_projects p,
		im_projects main_p
	where	h.user_id = :user_id_from_search
		and $h_day_in_dayweek
		and h.project_id = p.project_id
		and tree_ancestor_key(p.tree_sortkey, 1) = main_p.tree_sortkey
"
array set member_projects_hash {}
db_foreach open_projects $open_projects_sql {
    set member_projects_hash($open_project_id) 1
}


# ---------------------------------------------------------
# Has-Children? Used to disable super-projects with children
# ---------------------------------------------------------

set has_children_sql "
	select  parent_p.project_id as parent_id,
		child_p.project_id as child_id
	from
		im_projects main_p,
		im_projects parent_p,
		im_projects child_p
	where
		main_p.project_id in ($parent_project_sql) and
		tree_ancestor_key(parent_p.tree_sortkey, 1) = main_p.tree_sortkey and
		child_p.parent_id = parent_p.project_id
"

array set has_children_hash {}
array set tree_hash {}
array set has_parent_hash {}

set js_objects "" 
set js_obj_list "var obj_list = \["
set tree_parent_child_list [list]
set cnt 1 
db_foreach has_children $has_children_sql {
    set has_children_hash($parent_id) 1
    set has_parent_hash($child_id) 1

    # For JS client side  
    append js_objects "var obj_$cnt = {id:$child_id, parent:$parent_id};\n"
    append js_obj_list "obj_$cnt, "

    # 
    lappend tree_parent_child_list [list $parent_id $child_id]
    incr cnt
}

# We have to add for all top_parents an js object with parent:0 to make the tree working  
db_foreach rec $parent_project_sql {
    append js_objects "var obj_$cnt = {id:$project_id, parent:0};\n"
    append js_obj_list "obj_$cnt, "
    incr cnt
}

# remove last comma 
set js_obj_list "[string range $js_obj_list 0 end-2]\];" 


# ---------------------------------------------------------
# Execute query and format results
# ---------------------------------------------------------

db_multirow hours_multirow hours_timesheet $sql

# Sort the tree according to the specified sort order
multirow_sort_tree hours_multirow project_id parent_id sort_order

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# 
# Format the output
# 
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Don't show closed and deleted projects:
# The tree algorithm maintains a "closed_level"
# that determines the sub_level of the last closed
# intermediate project.

set results ""
set ctr 0
set nbsps "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
set old_project_id 0
set closed_level 0
set closed_status [im_project_status_open]
set old_parent_project_nr ""

set showing_child_elements_p 0
set top_project_id_saved -1
set last_level_shown -1
set level_entered_in_showing_child_elements -1

set filter_surpress_output_p 0

# If top_parent_project is shown because it contains search string, we can surpress path 
set top_parent_shown_p 0 

template::multirow foreach hours_multirow {
    #-- Init --# 
    set table_rows ""

    #-- -----------------------------------------------------------------------------------------------
    #-- The following code block does nothing but setting the variable 
    #--	  filter_surpress_output_p
    #-- which is used to determine the visibility of a row based on the search filter 
    #-- -----------------------------------------------------------------------------------------------

    if { "" != $search_task } {
	set search_task [string trim $search_task]
	if { !$showing_child_elements_p || $ctr==0 } {
	    if { [string first [string tolower $search_task] [string tolower $project_name]] == -1 } {
		set filter_surpress_output_p 1
	    } else {
		# Set mode
		set showing_child_elements_p 1
		# Save vars
		set last_level_shown $subproject_level
		set level_entered_in_showing_child_elements $subproject_level
		set top_project_id_saved $top_project_id
	    }
	} else {
	    # In mode "Show child elements"
	    if { $top_project_id_saved != $top_project_id } {
		# New top parent project
		# Reset
		set showing_child_elements_p 0
		# Save vars
		set top_project_id_saved $top_project_id
		
		if { [string first [string tolower $search_task] [string tolower $project_name]] == -1 } {
		    set filter_surpress_output_p 1
		} else {
		    # Set mode & last_level_shown
		    set showing_child_elements_p 1
		    set level_entered_in_showing_child_elements $subproject_level
		    set last_level_shown $subproject_level
		}
	    } else {
		if { $subproject_level == $last_level_shown } {
		    if { $level_entered_in_showing_child_elements >= $subproject_level} {
			# reset last_level_shown
			# Check for searchstring
			if { [string first [string tolower $search_task] [string tolower $project_name]] == -1 } {
			    set filter_surpress_output_p 1
			} else {
			    set last_level_shown $subproject_level
			}			
		    } else {
			set last_level_shown $subproject_level
		    }
		} elseif { $subproject_level > $last_level_shown } {
		    # show in all cases
		    set last_level_shown $subproject_level
		} else {
		    if { $level_entered_in_showing_child_elements >= $subproject_level} {
			# ns_log NOTICE "/intranet-timesheet2/www/hours/new:: Check for searchstring"
			if { [string first [string tolower $search_task] [string tolower $project_name]] == -1 } {
			    set showing_child_elements_p 0
			    set filter_surpress_output_p 1
			} else {
			    set last_level_shown $subproject_level
			}
		    } else {
			set last_level_shown $subproject_level
		    }
		}
	    }
	}
	set top_project_id_saved $top_project_id
    }
    
    # --------------------------------------------- 
    # Deal with the open and closed subprojects
    # A closed project will prevent all sub-projects from being displayed. 
    # So it "leaves a trace" by setting the "closed_level" to its's current level.
    # The "closed_status" will be reset to "open", as soon as the next project 
    # reaches the same "closed_level".

    # Check for log_p - if the project is in one of the closed states
    switch $task_visibility_scope {
	"main_project" - "specified" {
	    # Membership is this specific project not necessary - just check status
	    set log_p 1
	    if {[lsearch -exact $closed_stati $project_status_id] > -1} { set log_p 0 }
	}
	"sub_project" {
	    # Control is with subprojects, tasks are always considered open.
	    set log_p [info exists member_projects_hash($project_id)]
	    if {$project_type_id == [im_project_type_task]} { set log_p 1 }
	    if {$project_type_id == [im_project_type_ticket]} { set log_p 1 }
	}
	"task" {
	    # Control is with each task individually
	    set log_p [info exists member_projects_hash($project_id)]
	}
    }

    # --------------------------------------------- 
    # Pull out information about the project. Variables:
    #
    #	closed_status		Controls the tree open/close logic (see below)
    #	closed_level		Controls the tree open/close logic (see below)
    #
    #	log_on_parent_p		Can we log hours on a parent project? We might just log on the children...
    #	user_is_project_member_p The user is a direct member of the project.	
    #	project_is_task_p	Project is a task. Tasks are considered "open".
    #	solitary_main_project_p	Marks single main projects without children. Some costomers don't allow logging on them.
    #	project_has_children_p	Does the project have children?
    #	project_has_parents_p	Does the project have a parent?
    #	
    #	
    #	log_p			Variable that controls closed_status
    #	closed_p		Final conclusion: Can we log hour or not?

    # Can we log hours on a parent?
    set log_on_parent_p 1
    if {!$log_hours_on_parent_with_children_p && [info exists has_children_hash($project_id)]} { set log_on_parent_p 0 }

    # Check if the user is a member of the project
    set user_is_project_member_p [info exists member_projects_hash($project_id)]

    # Are we dealing with a task?
    set project_is_task_p [expr $project_type_id == [im_project_type_task] || $project_type_id == [im_project_type_ticket]]

    # Check if this project is a "solitary" main-project
    # There are some companies that want to avoid logging hours
    # on such solitary projects.
    set solitary_main_project_p 1
    if {[info exists has_children_hash($project_id)]} { set solitary_main_project_p 0 }
    if {[info exists has_parent_hash($project_id)]} { set solitary_main_project_p 0 }
    if {$log_hours_on_solitary_projects_p} { set solitary_main_project_p 0 }
    if {$closed_status == [im_project_status_closed]} { set solitary_main_project_p 0 }

    # "family" relationships
    set project_has_children_p [info exists has_children_hash($project_id)]
    set project_has_parents_p [info exists has_parent_hash($project_id)]

    # ---------------------------------------------
    # Tree open/close logic

    # Change back from a closed branch to an open branch
    set pnam [string range $project_name 0 10]
    if {$subproject_level <= $closed_level} {
	ns_log Notice "new: $pnam: action: reset to open"
	set closed_status [im_project_status_open]
	set closed_level 0
    }

    ns_log Notice "new: $pnam: p=$project_id, depth=$subproject_level, closed_level=$closed_level, status=$project_status"

    # We've just discovered a status change from open to closed:
    # Remember at what level this has happened to undo the change
    # once we're at the same level again:
    if {!$log_p && $closed_status == [im_project_status_open]} {
	ns_log Notice "new: $pnam: action: set to closed: log_p=$log_p, vis=$task_visibility_scope"
	set closed_status [im_project_status_closed]
	set closed_level $subproject_level
    }

    # ---------------------------------------------
    # Final decision: Should we log or not?
    # Check if the current tree-branch-status is "closed"
    set closed_p [expr $closed_status == [im_project_status_closed] || [lsearch $closed_stati $project_status_id] > -1]

    # ---------------------------------------------
    # Indent the project line
    #
    set indent ""
    set level $subproject_level
    set dots_for_filter ""
    while {$level > 0} {
	set indent "$nbsps$indent"
	set level [expr $level-1]
	append dots_for_filter "."
    }

    # ------------------------------------------------------------------------------------------
    # Insert intermediate header for every top-project
    # ------------------------------------------------------------------------------------------

    if {$parent_project_nr != $old_parent_project_nr } { 
	set project_name "<b>$project_name</b>"
	set project_nr "<b>$project_nr</b>"
	# Save information if Top Project has been shown 
	# If Top Project is not shown because of filter, we have to add this info to the task/subproject 
	# task or subproject 
	if { !$filter_surpress_output_p } { 
	    set top_parent_shown_p 1 
	    # Add an empty line after every main project
	    append table_rows "<tr class='rowplain @@visibility-class@@'><td colspan=99>&nbsp;</td></tr>\n" 
	} else { 
	    set top_parent_shown_p 0	
	}
	set old_parent_project_nr $parent_project_nr
    }

    # Set project title & URL
    set project_url [export_vars -base "/intranet/projects/view?" {project_id return_url}]
    if {$show_project_nr_p} { set ptitle "$project_nr - $project_name" } else { set ptitle $project_name }

    if { !$filter_surpress_output_p } { 
	if { !$top_parent_shown_p && $project_id != $top_project_id && "" != $search_task } {
	    # This row only serves as "title" row showing the top-parent project in case a "string search filter" us used  
	    append table_rows "<tr $tr_class([expr $ctr % 2])>\n<td>@@fold-icon-class@@"
	    append table_rows "<strong><a href='/intranet/projects/view?project_id=$top_project_id' style='text-decoration: none'>
					<span style='color:\#A9D0F5'>$top_parent_project_name $dots_for_filter</span></a></strong><br>"
	    append table_rows "</td></tr>"
	    set top_parent_shown_p 1
	}	
	append table_rows "<tr $tr_class([expr $ctr % 2]) id=\"${project_id}\" hidden_by=\"@@hidden_by@@\" fold_status=\"@@fold_status@@\" >\n<td><nobr>$indent @@fold-icon-class@@ <a href=\"$project_url\">$ptitle</a></nobr></td>\n" 
    }

    # ------------------------------------------------------------------------------
    # Create help texts to explain the user why certain projects aren't shown
    # ------------------------------------------------------------------------------
    set help_text ""
    if {$closed_p && (!$user_is_project_member_p && $project_is_task_p)} { 
	append help_text [lang::message::lookup "" intranet-timesheet2.Nolog_closed_p "The project or one of its parents has been closed or requires membership. "] 
    }
    if {![string eq "t" $edit_hours_p]} { append help_text [lang::message::lookup "" intranet-timesheet2.Nolog_edit_hours_p "The time period has been closed for editing. "] }
    if {!$log_on_parent_p} { append help_text [lang::message::lookup "" intranet-timesheet2.Nolog_log_on_parent_p "This project has sub-projects or tasks. "] }
    if {$solitary_main_project_p} { 
	append help_text [lang::message::lookup "" intranet-timesheet2.Nolog_solitary_main_project_p "This is a 'solitary' main project. Your system is configured in such a way, that you can't log hours on it. "] 
    }
    
    # Not a member: This isn't relevant in all modes:
    switch $task_visibility_scope {
	"main_project" - "specified" {
	    # user_is_project_member_p not relevant at all.
	    set show_member_p 0
	}
	"sub_project" {
	    # user_is_project_member_p only relevant for projects, not for tasks,
	    # because it is the "controlling" (sub-) project that determines.
	    set show_member_p [expr !$project_is_task_p]
	}
	"task" {
	    # user_is_project_member_p relevant everywhere
	    set show_member_p 1
	}
	default { 
	    set show_member_p 0
	}
    }

    if {$show_member_p && !$user_is_project_member_p} { append help_text [lang::message::lookup "" intranet-timesheet2.Not_member_of_project "You are not a member of this project. "] }

    # -----------------------------------------------
    # Write out help and debug information
    set help_gif ""
    if {"" != $help_text} { set help_gif [im_gif -translate_p 0 help $help_text] }

    set debug_html ""
    if {$debug} {
	set debug_html "
	<nobr>
	sol=$solitary_main_project_p,
	mem=$user_is_project_member_p,
	log=$log_p,
	clo=$closed_p,
	</nobr>
	"
    }

    if { !$filter_surpress_output_p } { append table_rows "<td>$help_gif $debug_html</td>\n" }

    # -----------------------------------------------
    # Write out logging input fields - either for Daily View (1 field) or Weekly View (7 fields)

    set i 0 
    foreach j $weekly_logging_days {
	set julian_day_offset [expr $julian_date + $i]
	set hours ""
	set note ""
	set internal_note ""
	set material_id $default_material_id
	set material "Default"
	set conf_status_id ""
	set key "$project_id-$julian_day_offset"
	
	if {[info exists hours_hours($key)]} { set hours $hours_hours($key) }
	if {[info exists hours_note($key)]} { set note $hours_note($key) }
	if {[info exists hours_internal_note($key)]} { set internal_note $hours_internal_note($key) }
	if {[info exists hours_material_id($key)]} { set material_id $hours_material_id($key) }
	if {[info exists hours_material($key)]} { set material $hours_material($key) }
	if {[info exists hours_conf_status_id($key)]} { set conf_status_id $hours_conf_status_id($key) }
	
	# Determine whether the hours have already been included in a timesheet invoice
	set invoice_id 0
	set invoice_key "$project_id-$julian_day_offset"
	if {[info exists hours_invoice_hash($invoice_key)]} { set invoice_id $hours_invoice_hash($invoice_key) }
	
	set blocked_by_wf_help ""
	if { "" ==  $conf_status_id || "17000" == $conf_status_id } {
	    set blocked_by_wf_p 0 
	} else {
	    set blocked_by_wf_p 1
	    set blocked_by_wf_help [im_gif -translate_p 0 help [lang::message::lookup "" intranet-timesheet2.BlockedbyWF "Blocked by TS Approval Workflow"]]
	}
	
	ns_log Notice "xxx: $conf_status_id"

	if { "t" == $edit_hours_p && $log_on_parent_p && !$invoice_id && !$solitary_main_project_p && !$closed_p && !$filter_surpress_output_p && !$blocked_by_wf_p } {
	    # Write editable entries.
	    append table_rows "<td><input name=hours${i}.$project_id size=5 MAXLENGTH=5 value=\"$hours\"></td>\n"
	    if {!$show_week_p} {
		append table_rows "<td><input name=notes0.$project_id size=$external_comment_size value=\"[ns_quotehtml [value_if_exists note]]\"></td>\n"
		if {$internal_note_exists_p} { append table_rows "<td><input name=internal_notes0.$project_id size=$internal_comment_size value=\"[ns_quotehtml [value_if_exists internal_note]]\"></td>\n" }
		if {$materials_p} { append table_rows "<td>[im_select -translate_p 0 -ad_form_option_list_style_p 1 materials0.$project_id $material_options $material_id]</td>\n" }
	    }
	} else {
	    if { $filter_surpress_output_p } {
		# Filter in use - write only hidden fields 
		append table_rows "<input type=hidden name=hours${i}.$project_id value=\"$hours\">\n"
		if {!$show_week_p} {
		    append table_rows "<input type=hidden name=notes0.$project_id value=\"[ns_quotehtml [value_if_exists note]]\">\n"
		    if {$internal_note_exists_p} { 
			append table_rows "<input type='hidden' name=internal_notes0.$project_id value=\"[ns_quotehtml [value_if_exists internal_note]]\">\n" 
		    }
		    if {$materials_p} { append table_rows "<input type=hidden name=materials0.$project_id value=$material_id>\n" }
		}   
	    } else {
		# Write Disabled because we can't log hours on this one
		append table_rows "<td>$hours $blocked_by_wf_help <input type=hidden name=hours${i}.$project_id value=\"$hours\"></td>\n"
		if {!$show_week_p} {
		    append table_rows "<td>[ns_quotehtml [value_if_exists note]] <input type=hidden name=notes0.$project_id value=\"[ns_quotehtml [value_if_exists note]]\"></td>\n"
		    if {$internal_note_exists_p} { 
			append table_rows "<td>[ns_quotehtml [value_if_exists internal_note]] <input type='hidden' name=internal_notes0.$project_id value=\"[ns_quotehtml [value_if_exists internal_note]]\"></td>\n" 
		    }
		    if {$materials_p} { append table_rows "<td>$material <input type=hidden name=materials0.$project_id value=$material_id></td>\n" }
		}   
	    }
	}
	incr i
    }; # For each weekday
    if { !$filter_surpress_output_p } { append table_rows "</tr>\n" }
    
    # -- ----------------------------------------------------------
    # -- Implementing fold in/out logic 
    # -- ----------------------------------------------------------

    # Some organizations might prefer to show elements as "folded in" by default
    if { $default_is_fold_in_p } {
	if { ![info exists collapsed_hash($project_id)] } {
	    set collapsed_hash($project_id) c
	}
    }

    # Add icon fold-in/fold-out after first <td> on main project level & define visibility  
    if { "" == $search_task } {
	# SET VISIBILITY 
	# Always show if Top_Parent 
	if { [info exists has_parent_hash($project_id)] } {
	    set parent_ids [tree_list_get_all_parents $tree_parent_child_list $project_id ""]
	    foreach id $parent_ids {
		if { [info exists collapsed_hash($id)] && "c" == $collapsed_hash($id) } {
		    regsub -all "@@hidden_by@@" $table_rows "$id" table_rows
		    regsub -all "@@visibility-class@@" $table_rows "row_hidden" table_rows
		    break
		}
	    }
	    # If already replaced w/ for-each loop above, this has no effect
	    regsub -all "@@hidden_by@@" $table_rows "" table_rows
	    regsub -all "@@visibility-class@@" $table_rows "row_visible" table_rows
	} else {
	    # This project as no parents, must be a Top-Project --> always show
	    regsub -all "@@hidden_by@@" $table_rows "" table_rows
	    regsub -all "@@visibility-class@@" $table_rows "row_visible" table_rows
	}

	# SET ICON & FOLD-STATUS 	   
	# Set icon only when task has children 
	if { [info exists has_children_hash($project_id)] } {
	    set in_out "in" ; # "minus"
	    set fold_status "o" 
	    if { [info exists collapsed_hash($project_id)] && "c" == $collapsed_hash($project_id) } {
		set in_out "out"
		set fold_status "c"
	    } 
	    regsub -all "@@fold-icon-class@@" $table_rows "<input class=\"fold_${in_out}_link\" id=\"lnk$project_id\" type=\"button\" value=\"\" onclick=\"toggle_visibility('lnk$project_id', '${project_id}');\">" table_rows	   
	    regsub -all "@@fold_status@@" $table_rows $fold_status table_rows		  
	} else {
	    regsub -all "@@fold-icon-class@@" $table_rows "\\&nbsp;\\&nbsp;\\&nbsp;" table_rows
	    regsub -all "@@fold_status@@" $table_rows "o" table_rows
	}
    } else {
	# Search Mode - show everything  
	regsub -all "@@fold-icon-class@@" $table_rows "" table_rows
	regsub -all "@@visibility-class@@" $table_rows "row_visible" table_rows
    }

    append results $table_rows 

    # -- manage/reset loop vars  
    incr ctr
    set filter_surpress_output_p 0
}


if { [empty_string_p results] } {
    append results "
<tr>
  <td align=center><b>
    [_ intranet-timesheet2.lt_There_are_currently_n_1]<br>
    [_ intranet-timesheet2.lt_Please_notify_your_ma]
  </b></td>
</tr>\n"
}

set export_form_vars [export_form_vars return_url julian_date user_id_from_search show_week_p]


# ---------------------------------------------------------
# Format the weekly column headers
# ---------------------------------------------------------

# Date format for formatting
set weekly_column_date_format "YYYY<br>MM-DD"
set week_header_html ""


set i 0 
foreach j $weekly_logging_days {
    set julian_day_offset [expr $julian_week_start + $i]
    im_security_alert_check_integer -location "intranet-timesheet2/hours/new.tcl" -value $julian_day_offset
    set header_day_of_week [util_memoize [list db_string day_of_week "select to_char(to_date('$julian_day_offset', 'J'), 'Dy')"]]
    set header_day_of_week_l10n [lang::message::lookup "" intranet-timesheet2.Day_of_week_$header_day_of_week $header_day_of_week]
    set header_date [util_memoize [list db_string header "select to_char(to_date('$julian_day_offset', 'J'), '$weekly_column_date_format')"]]
    append week_header_html "<th>$header_day_of_week_l10n<br>$header_date</th>\n"
    incr i
}

# ---------------------------------------------------------
# Navbars
# ---------------------------------------------------------

set left_navbar_html "
      <div class='filter-block'>
	<div class='filter-title'>
	    Timesheet Filters
	</div>

	<form action=new method=GET>
	<!-- don't include return_url in the export_form_vars, as it includes the old user -->
	[export_form_vars julian_date show_week_p] 
	<table border=0 cellpadding=1 cellspacing=1>
	<tr>
	    <td>[lang::message::lookup "" intranet-timesheet2.Project_br_Name "Project<br>Name"]</td>
	    <td>[im_project_select -include_empty_p 1 -include_empty_name "" -project_status_id [im_project_status_open] -exclude_subprojects_p 1 project_id $project_id_for_default "open"]</td>
	</tr>
"
if {$add_hours_all_p} {
    append left_navbar_html "
	<tr>
	    <td>[lang::message::lookup "" intranet-timesheet2.Log_hours_for_user "Log Hours<br>for User"]</td>
	    <td>[im_user_select -include_empty_p 1 -include_empty_name "" user_id_from_search $user_id_from_search]</td>
	</tr>
    "
}

append left_navbar_html "
	<tr>
		<td>[lang::message::lookup "" intranet-timesheet2.SearchTask "Search<br>by Name"]:</td>
		<td><input type='text' size='17' maxlength='30' name='search_task' value='$search_task'></td>
	</tr>
"

append left_navbar_html "
	<tr><td></td><td><input type=submit value='Go'></td></tr>
	</table>
	</form>
      </div>
"

append left_navbar_html "
      <div class='filter-block'>
	 <div class='filter-title'>
	    #intranet-timesheet2.Other_Options#
	 </div>
	 <ul>
	    <li>
	      <a href='$different_date_url'>
		#intranet-timesheet2.lt_Log_hours_for_a_diffe#
	      </a>
	    </li>
"

if {$current_user_id == $user_id_from_search && $add_absences_p} {
    append left_navbar_html "
	    <li><a href='$absences_url'>$absences_link_text</a></li>
    "
}

if {[im_permission $current_user_id view_projects_all]} {
    append left_navbar_html "
	    <li><a href='$different_project_url'>#intranet-timesheet2.lt_Add_hours_on_other_pr#</A></li>
    "
}
if {![empty_string_p $return_url]} {
    append left_navbar_html "
	    <li><a href='$return_url'>#intranet-timesheet2.lt_Return_to_previous_pa#</a></li>
    "
}

append left_navbar_html "
	    <!-- Dynamically added menu links -->
	    $menu_links_html

	 </ul>
      </div>
"
