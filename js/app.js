/* =====================================================
   AADS STATS APP - SHARED JAVASCRIPT UTILITIES
   Atlantic Amateur Darts Series
   ===================================================== */

// ===== CONFIGURATION =====
const SUPABASE_URL = 'https://ynplcupdtrwcsbwtnass.supabase.co'; // Replace with your Supabase project URL
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlucGxjdXBkdHJ3Y3Nid3RuYXNzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY1NzgwNzksImV4cCI6MjA4MjE1NDA3OX0.f9UJbeIfkdN6sxYYnOEKM7d8UgZEMIzUyKBlp5DQkXs'; // Replace with your anon key
const ADMIN_SECRET = 'AADS_Admin_2025_Secure_Key_39546'; // Replace with your admin secret

// Initialize Supabase client
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ===== NAVIGATION HISTORY =====
class NavigationHistory {
    constructor() {
        this.history = JSON.parse(sessionStorage.getItem('navHistory') || '[]');
    }

    push(url) {
        this.history.push(url);
        sessionStorage.setItem('navHistory', JSON.stringify(this.history));
    }

    pop() {
        const previous = this.history.pop();
        sessionStorage.setItem('navHistory', JSON.stringify(this.history));
        return previous;
    }

    goBack() {
        const previous = this.pop();
        if (previous) {
            window.location.href = previous;
        } else {
            window.location.href = 'index.html'; // Default to home
        }
    }
}

const navHistory = new NavigationHistory();

// Track current page
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        navHistory.push(window.location.pathname);
    });
} else {
    navHistory.push(window.location.pathname);
}

// ===== AUTOCOMPLETE FUNCTIONALITY =====
class Autocomplete {
    constructor(inputElement, dataSource, onSelect) {
        this.input = inputElement;
        this.dataSource = dataSource; // Array or async function
        this.onSelect = onSelect;
        this.currentFocus = -1;
        this.init();
    }

    init() {
        // Create suggestions container
        this.suggestionsContainer = document.createElement('div');
        this.suggestionsContainer.className = 'autocomplete-suggestions hidden';
        this.input.parentNode.appendChild(this.suggestionsContainer);

        // Event listeners
        this.input.addEventListener('input', () => this.handleInput());
        this.input.addEventListener('keydown', (e) => this.handleKeydown(e));
        document.addEventListener('click', (e) => {
            if (!this.input.contains(e.target)) {
                this.closeSuggestions();
            }
        });
    }

    async handleInput() {
        const value = this.input.value;
        if (!value) {
            this.closeSuggestions();
            return;
        }

        // Get data
        const data = typeof this.dataSource === 'function' 
            ? await this.dataSource() 
            : this.dataSource;

        // Filter by first letter match
        const filtered = data.filter(item => {
            const name = typeof item === 'string' ? item : item.name;
            return name.toLowerCase().startsWith(value.toLowerCase());
        });

        this.showSuggestions(filtered);
    }

    showSuggestions(items) {
        this.closeSuggestions();
        
        if (items.length === 0) return;

        this.suggestionsContainer.classList.remove('hidden');
        
        items.forEach((item, index) => {
            const div = document.createElement('div');
            div.className = 'autocomplete-suggestion';
            div.textContent = typeof item === 'string' ? item : item.name;
            div.addEventListener('click', () => this.selectItem(item));
            this.suggestionsContainer.appendChild(div);
        });
    }

    selectItem(item) {
        const name = typeof item === 'string' ? item : item.name;
        this.input.value = name;
        this.closeSuggestions();
        if (this.onSelect) {
            this.onSelect(item);
        }
    }

    handleKeydown(e) {
        const suggestions = this.suggestionsContainer.querySelectorAll('.autocomplete-suggestion');
        
        if (e.keyCode === 40) { // Down arrow
            this.currentFocus++;
            this.setActive(suggestions);
        } else if (e.keyCode === 38) { // Up arrow
            this.currentFocus--;
            this.setActive(suggestions);
        } else if (e.keyCode === 13) { // Enter
            e.preventDefault();
            if (this.currentFocus > -1 && suggestions[this.currentFocus]) {
                suggestions[this.currentFocus].click();
            }
        }
    }

    setActive(suggestions) {
        if (!suggestions) return;
        this.removeActive(suggestions);
        
        if (this.currentFocus >= suggestions.length) this.currentFocus = 0;
        if (this.currentFocus < 0) this.currentFocus = suggestions.length - 1;
        
        suggestions[this.currentFocus]?.classList.add('active');
    }

    removeActive(suggestions) {
        suggestions.forEach(s => s.classList.remove('active'));
    }

    closeSuggestions() {
        this.suggestionsContainer.innerHTML = '';
        this.suggestionsContainer.classList.add('hidden');
        this.currentFocus = -1;
    }
}

// ===== DATA FETCHING FUNCTIONS =====

// Fetch all players
async function fetchPlayers() {
    const { data, error } = await supabase
        .from('players')
        .select('*')
        .order('name');
    
    if (error) {
        console.error('Error fetching players:', error);
        return [];
    }
    return data;
}

// Fetch all series
async function fetchSeries() {
    const { data, error } = await supabase
        .from('series')
        .select('*')
        .order('id');
    
    if (error) {
        console.error('Error fetching series:', error);
        return [];
    }
    return data;
}

// Fetch events for a series
async function fetchEvents(seriesId) {
    const { data, error } = await supabase
        .from('events')
        .select(`
            *,
            winner:winner_id(name)
        `)
        .eq('series_id', seriesId)
        .order('event_number');
    
    if (error) {
        console.error('Error fetching events:', error);
        return [];
    }
    return data;
}

// Fetch matches for an event
async function fetchMatches(eventId) {
    const { data, error } = await supabase
        .from('matches')
        .select(`
            *,
            player1:player_1_id(name),
            player2:player_2_id(name),
            winner:winner_id(name)
        `)
        .eq('event_id', eventId)
        .order('id');
    
    if (error) {
        console.error('Error fetching matches:', error);
        return [];
    }
    return data;
}

// Fetch match stats
async function fetchMatchStats(matchId) {
    const { data, error } = await supabase
        .from('match_stats')
        .select(`
            *,
            player:player_id(name)
        `)
        .eq('match_id', matchId);
    
    if (error) {
        console.error('Error fetching match stats:', error);
        return [];
    }
    return data;
}

// ===== STANDINGS CALCULATION =====
function calculateGroupStandings(matches) {
    const playerStats = {};

    matches.forEach(match => {
        // Player 1 stats
        if (!playerStats[match.player_1_id]) {
            playerStats[match.player_1_id] = {
                id: match.player_1_id,
                name: match.player1.name,
                matches: 0,
                legWins: 0,
                legLosses: 0
            };
        }
        playerStats[match.player_1_id].matches++;
        playerStats[match.player_1_id].legWins += match.p1_legs;
        playerStats[match.player_1_id].legLosses += match.p2_legs;

        // Player 2 stats
        if (!playerStats[match.player_2_id]) {
            playerStats[match.player_2_id] = {
                id: match.player_2_id,
                name: match.player2.name,
                matches: 0,
                legWins: 0,
                legLosses: 0
            };
        }
        playerStats[match.player_2_id].matches++;
        playerStats[match.player_2_id].legWins += match.p2_legs;
        playerStats[match.player_2_id].legLosses += match.p1_legs;
    });

    // Convert to array and calculate leg difference
    const standings = Object.values(playerStats).map(player => ({
        ...player,
        legDifference: player.legWins - player.legLosses
    }));

    // Sort by leg wins, then leg difference
    standings.sort((a, b) => {
        if (b.legWins !== a.legWins) {
            return b.legWins - a.legWins;
        }
        return b.legDifference - a.legDifference;
    });

    // Assign positions
    standings.forEach((player, index) => {
        player.position = index + 1;
    });

    return standings;
}

// ===== ADMIN FUNCTIONS (With x-admin-secret header) =====

async function adminRequest(table, operation, data) {
    const headers = {
        'x-admin-secret': ADMIN_SECRET
    };

    let query;
    
    switch(operation) {
        case 'insert':
            query = supabase.from(table).insert(data, { headers });
            break;
        case 'update':
            query = supabase.from(table).update(data.values, { headers }).eq('id', data.id);
            break;
        case 'upsert':
            query = supabase.from(table).upsert(data, { headers });
            break;
        case 'delete':
            query = supabase.from(table).delete({ headers }).eq('id', data.id);
            break;
    }

    const { data: result, error } = await query;
    
    if (error) {
        console.error(`Admin ${operation} error:`, error);
        throw error;
    }
    
    return result;
}

// Log admin action
async function logAdminAction(seriesId, eventId, action, stage, description) {
    try {
        await adminRequest('edit_log', 'insert', {
            series_id: seriesId,
            event_id: eventId,
            admin_action: action,
            stage_affected: stage,
            changes_description: description
        });
    } catch (error) {
        console.error('Failed to log admin action:', error);
    }
}

// ===== UI HELPER FUNCTIONS =====

function showLoading(elementId) {
    const element = document.getElementById(elementId);
    if (element) {
        element.innerHTML = '<div class="loading-spinner"></div>';
    }
}

function hideLoading(elementId) {
    const element = document.getElementById(elementId);
    if (element) {
        element.innerHTML = '';
    }
}

function showModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.add('active');
    }
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.remove('active');
    }
}

function showAlert(message, type = 'info') {
    const alertDiv = document.createElement('div');
    alertDiv.className = `alert-banner ${type}`;
    alertDiv.innerHTML = `
        <span>${message}</span>
        <span class="close-alert" onclick="this.parentElement.remove()">×</span>
    `;
    
    const container = document.querySelector('.container') || document.body;
    container.insertBefore(alertDiv, container.firstChild);
    
    // Auto-remove after 5 seconds
    setTimeout(() => alertDiv.remove(), 5000);
}

// Format number with commas
function formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// Calculate percentage
function calculatePercentage(part, total) {
    if (total === 0) return 0;
    return ((part / total) * 100).toFixed(2);
}

// ===== REAL-TIME SUBSCRIPTIONS =====

function subscribeToTable(table, callback) {
    const channel = supabase
        .channel(`${table}-changes`)
        .on('postgres_changes', 
            { event: '*', schema: 'public', table: table }, 
            callback
        )
        .subscribe();
    
    return channel;
}

// ===== BREADCRUMB GENERATION =====

function generateBreadcrumb(parts) {
    const breadcrumbDiv = document.querySelector('.breadcrumb');
    if (!breadcrumbDiv) return;

    const links = parts.map((part, index) => {
        if (index === parts.length - 1) {
            return `<span>${part.text}</span>`;
        }
        return `<a href="${part.url}">${part.text}</a>`;
    }).join(' > ');

    breadcrumbDiv.innerHTML = links;
}

// ===== EXPORT FUNCTIONS =====
window.AADS = {
    supabase,
    navHistory,
    Autocomplete,
    fetchPlayers,
    fetchSeries,
    fetchEvents,
    fetchMatches,
    fetchMatchStats,
    calculateGroupStandings,
    adminRequest,
    logAdminAction,
    showLoading,
    hideLoading,
    showModal,
    closeModal,
    showAlert,
    formatNumber,
    calculatePercentage,
    subscribeToTable,
    generateBreadcrumb
};


